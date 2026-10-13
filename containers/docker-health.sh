#!/usr/bin/env bash
# Docker 容器健康检查
# 在宿主机由 cron 调用；每次仅检查一轮。

set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 1
docker_name=${DOCKER_NAME:-}
state_dir=${HEALTH_STATE_DIR:-$script_dir/.docker-health-state}
log_file=${HEALTH_LOG_FILE:-$script_dir/docker-health.log}
cmd=${CMD:-}

for dependency in docker flock; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf '缺少必要命令：%s\n' "$dependency" >&2
        exit 1
    fi
done
[ -n "$docker_name" ] || { echo 'DOCKER_NAME 不能为空' >&2; exit 1; }
mkdir -p "$state_dir" || exit 1
# 避免 cron 重叠执行导致重复重启；进程退出后锁由系统释放。
exec 9>"$state_dir/lock" || exit 1
flock -n 9 || exit 0

write_attempts() {
    local file=$1 value=$2 tmp=$1.tmp.$$
    if printf '%s\n' "$value" >"$tmp" && mv -f -- "$tmp" "$file"; then return 0; fi
    rm -f -- "$tmp"
    return 1
}

containers=$(docker ps -a --no-trunc --format '{{.ID}} {{.Names}}' 9>&-) || exit 1
result=0
while read -r container_id container_name; do
    [ -n "$container_id" ] || continue
    case "$container_name" in "$docker_name"*) ;; *) continue ;; esac
    state_file=$state_dir/$container_id
    status=$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id" 9>&-) || {
        result=1
        continue
    }
    attempts=0
    if [ -f "$state_file" ]; then
        read -r attempts < "$state_file" || attempts=0
    fi
    case "$attempts" in 0|1|2|3) ;; *)
        printf '无效的重启计数文件：%s\n' "$state_file" >&2
        result=1
        continue
        ;;
    esac
    case "$status" in
        'running starting'|restarting\ *|removing\ *|paused\ *) continue ;;
        'running none'|'running healthy')
            if [ "$attempts" -gt 0 ]; then
                recovery_time=$(date '+%Y-%m-%dT%H:%M:%S%z')
                # 日志写入成功后才清零，避免写入失败后丢失恢复事件。
                if ! printf '%s container=%s event=recovered status="%s"\n' \
                    "$recovery_time" "$container_name" "$status" >> "$log_file"; then
                    result=1
                    continue
                fi
            fi
            if ! write_attempts "$state_file" 0; then
                result=1
                continue
            fi
            if [ "$attempts" -gt 0 ] && [ -n "$cmd" ]; then
                if ! CONTAINER_NAME="$container_name" CONTAINER_ID="$container_id" \
                    EVENT_TIME="$recovery_time" CONTAINER_EVENT=recovered RECOVERY_TIME="$recovery_time" \
                    RESTART_TIME='' RESTART_ATTEMPT=0 RESTART_RESULT='' \
                    CONTAINER_STATUS="$status" sh -c "$cmd" 9>&-; then
                    printf '容器 %s 的恢复 CMD 执行失败\n' "$container_name" >&2
                    result=1
                fi
            fi
            continue
            ;;
    esac
    result=1
    [ "$attempts" -lt 3 ] || continue
    # 先持久化次数，失败的重启也占用额度，防止持续异常无限重试。
    attempts=$((attempts + 1))
    if ! write_attempts "$state_file" "$attempts"; then
        result=1
        continue
    fi
    if docker restart "$container_id" 9>&- >/dev/null; then
        restart_result=success
    else
        restart_result=failed
        result=1
    fi
    restart_time=$(date '+%Y-%m-%dT%H:%M:%S%z')
    if ! printf '%s container=%s attempt=%s result=%s status="%s"\n' \
        "$restart_time" "$container_name" "$attempts" "$restart_result" "$status" >> "$log_file"; then
        result=1
    fi
    if [ -n "$cmd" ]; then
        if ! CONTAINER_NAME="$container_name" CONTAINER_ID="$container_id" \
            EVENT_TIME="$restart_time" CONTAINER_EVENT=restart RECOVERY_TIME='' \
            RESTART_TIME="$restart_time" RESTART_ATTEMPT="$attempts" \
            RESTART_RESULT="$restart_result" CONTAINER_STATUS="$status" sh -c "$cmd" 9>&-; then
            printf '容器 %s 的 CMD 执行失败\n' "$container_name" >&2
            result=1
        fi
    fi
done <<EOF_CONTAINERS
$containers
EOF_CONTAINERS
exit "$result"
