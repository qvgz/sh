#!/usr/bin/env bash
# Compose 容器更新
# 通过参数修改指定标签值
set -u
set -o pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 1
env_file=${ENV_FILE:-$script_dir/.env.prod}
log_file=${LOG_FILE:-$script_dir/env-update.log}
case "$env_file" in /*) ;; *) env_file=$script_dir/$env_file ;; esac
case "$log_file" in /*) ;; *) log_file=$script_dir/$log_file ;; esac
image=unknown
old_image=unknown
old_value=unknown
repository=unknown
tag_value=${2:-unknown}
test_only=0
result=失败
tmp_env=''

# shellcheck disable=SC2329 # 由 EXIT trap 调用。
finish() {
    local status=$? line
    trap - EXIT
    [ -z "$tmp_env" ] || rm -f -- "$tmp_env"
    if [ "$test_only" -eq 0 ]; then
        if [ "$result" = 异常 ]; then
            line="$(date '+%Y-%m-%dT%H:%M:%S%z') 异常 $image 标签更新失败"
        elif [ "$result" = 回滚 ]; then
            line="$(date '+%Y-%m-%dT%H:%M:%S%z') 回滚 $image -> $old_value"
        else
            line="$(date '+%Y-%m-%dT%H:%M:%S%z') $result $old_image -> $tag_value"
        fi
        printf '%s\n' "$line"
        printf '%s\n' "$line" >> "$log_file" || status=1
    fi
    exit "$status"
}
[ "${3:-}" != -t ] || test_only=1
trap finish EXIT
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ] || { [ "$#" -eq 3 ] && [ "$3" != -t ]; }; then
    printf '用法：%s <TAG_NAME> <TAG_VALUE> [-t]\n' "$0" >&2
    exit 1
fi
tag_name=$1
# 无效输入不直接写入日志，防止换行破坏单行格式。
if ! [[ "$tag_value" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    tag_value=unknown
    exit 1
fi
[[ "$tag_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || exit 1

compose_up() {
    env "$tag_name=$1" docker compose -f "$compose_file" --env-file "$env_file" up -d 9>&-
}

run_update() {
    local dependency images placeholder
    for dependency in docker yq flock; do
        command -v "$dependency" >/dev/null || return 1
    done
    yq --version | grep -Eq 'version v4\.' || return 1
    cd -- "$script_dir" || return 1
    [ -f "$env_file" ] && [ ! -L "$env_file" ] || return 1
    # 规范化父目录，防止不同的相对路径绕过同一把锁。
    env_file=$(CDPATH='' cd -- "$(dirname -- "$env_file")" && printf '%s/%s' "$PWD" "$(basename -- "$env_file")") || return 1
    exec 9>"$env_file.lock" || return 1
    flock -n 9 || { printf '环境文件正在更新：%s\n' "$env_file" >&2; return 1; }
    compose_file=$script_dir/compose.yaml
    placeholder="\${$tag_name}"
    images=$(PLACEHOLDER="$placeholder" yq -r 'explode(.) | [.services[].image // "" | select(contains(strenv(PLACEHOLDER)))] | unique | .[]' \
        "$compose_file" 9>&- ) || return 1
    [ -n "$images" ] && [[ "$images" != *$'\n'* ]] || return 1
    [[ "$images" == *":$placeholder" ]] || return 1
    repository=${images%":$placeholder"}
    [[ -n "$repository" && "$repository" != *'$'* && ! "$repository" =~ [[:space:]] ]] || return 1
    image=$repository:$tag_value
    # 只读取变量，绝不 source 环境文件；重复定义取最后一个。
    old_value=$(awk -v name="$tag_name" '
        $0 ~ "^[ \t]*(export[ \t]+)?" name "[ \t]*=" {
            found=1
            value=$0
            sub(/^[^=]*=[ \t]*/, "", value)
            sub(/\r$/, "", value)
            sub(/[ \t]+#.*/, "", value)
            sub(/[ \t]+$/, "", value)
            if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) value=substr(value, 2, length(value)-2)
        }
        END { if (!found) exit 1; print value }
    ' "$env_file") || { printf '环境文件中不存在变量：%s\n' "$tag_name" >&2; return 1; }
    [[ "$old_value" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || return 1
    old_image=$repository:$old_value
    [ "$tag_value" != "$old_value" ] || return 1
    docker pull "$image" 9>&- || return 1
    [ "$test_only" -eq 0 ] || return 0

    tmp_env=$(mktemp "$env_file.tmp.XXXXXXXX") || return 1
    # 复制元数据后重写临时文件；失败时不替换原文件。
    cp -p -- "$env_file" "$tmp_env" || return 1
    awk -v name="$tag_name" -v value="$tag_value" '
        $0 ~ "^[ \t]*(export[ \t]+)?" name "[ \t]*=" {
            ending=($0 ~ /\r$/ ? "\r" : "")
            print name "=" value ending
            found=1
            next
        }
        { print }
        END { if (!found) exit 1 }
    ' "$env_file" > "$tmp_env" || return 1
    # 先准备临时文件，避免准备失败时已经更新容器。
    if compose_up "$tag_value"; then
        if ! mv -f -- "$tmp_env" "$env_file"; then
            result=异常
            return 1
        fi
        tmp_env=''
        result=成功
        return 0
    fi
    result=回滚
    # 回滚是尽力恢复，不额外验证运行状态；本次更新仍返回失败。
    compose_up "$old_value" || :
    return 1
}

if [ "$test_only" -eq 1 ]; then
    run_update || exit 1
else
    run_update >/dev/null 2>&1 || exit 1
fi
exit 0
