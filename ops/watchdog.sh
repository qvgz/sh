#!/bin/bash
# 进程守护，兼容 CentOS 5（Bash 3.2）
# 配置 watchdog.conf 每行：匹配串|启动命令，可配置 0~N 条

INTERVAL=${1:-20}
# 同一配置两次启动的最短间隔（秒）
RETRY_INTERVAL=${RETRY_INTERVAL:-30}
# 进程未恢复时最多启动次数
MAX_START=3

case "$INTERVAL" in
    '' | *[!0-9]*) INTERVAL=0 ;;
esac
if [ $# -gt 1 ] || [ "$INTERVAL" -le 0 ]; then
    echo "用法: $0 [正整数检查间隔秒数，默认 20]" >&2
    exit 1
fi
case "$RETRY_INTERVAL" in
    '' | *[!0-9]*)
        echo "RETRY_INTERVAL 须为非负整数: $RETRY_INTERVAL" >&2
        exit 1
        ;;
esac

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
CONF_FILE="$SCRIPT_DIR/watchdog.conf"
LOG_FILE="$SCRIPT_DIR/watchdog.log"
LOCK_FILE="$SCRIPT_DIR/watchdog.lock"

for cmd in pgrep flock setsid date sleep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "缺少命令: $cmd" >&2
        exit 1
    fi
done

if [ ! -r "$CONF_FILE" ]; then
    echo "配置不可读: $CONF_FILE" >&2
    exit 1
fi
if ! : >>"$LOG_FILE"; then
    echo "日志不可写: $LOG_FILE" >&2
    exit 1
fi

# 防止重复运行
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "watchdog 已在运行: $SCRIPT_DIR" >&2
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

# Bash 3.2 无关联数组：用平行数组按配置行记录上次启动时间、未恢复期间的启动次数
STATE_KEYS=()
STATE_LAST=()
STATE_COUNT=()
STATE_GAVEUP=()
# 查找配置行状态，设置 STATE_IDX，未找到为 -1
find_state() {
    local i=0
    STATE_IDX=-1
    while [ $i -lt ${#STATE_KEYS[@]} ]; do
        if [ "${STATE_KEYS[i]}" = "$1" ]; then
            STATE_IDX=$i
            return
        fi
        i=$((i + 1))
    done
}
new_state() {
    STATE_IDX=${#STATE_KEYS[@]}
    STATE_KEYS[STATE_IDX]=$1
    STATE_LAST[STATE_IDX]=0
    STATE_COUNT[STATE_IDX]=0
    STATE_GAVEUP[STATE_IDX]=0
}

check_once() {
    local line pattern cmd now elapsed ret n=0
    if [ ! -r "$CONF_FILE" ]; then
        log "配置不可读，跳过本轮: $CONF_FILE"
        return
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        line=${line%$'\r'}
        line=${line#"${line%%[![:space:]]*}"}
        case "$line" in
            '' | '#'*) continue ;;
            *'|'*) ;;
            *)
                log "第 $n 行跳过：缺少 |"
                continue
                ;;
        esac
        pattern=${line%%|*}
        cmd=${line#*|}
        if [ -z "$pattern" ] || [ -z "$cmd" ]; then
            log "第 $n 行跳过：匹配串或启动命令为空"
            continue
        fi

        pgrep -f -- "$pattern" >/dev/null 2>&1
        ret=$?
        if [ $ret -ne 0 ] && [ $ret -ne 1 ]; then
            log "第 $n 行跳过：pgrep 失败 code=$ret，检查匹配串: $pattern"
            continue
        fi
        find_state "$line"

        if [ $ret -eq 0 ]; then
            # 进程存在：此前有过启动则记录恢复并清零
            if [ $STATE_IDX -ge 0 ] && [ "${STATE_COUNT[STATE_IDX]}" -gt 0 ]; then
                log "进程已恢复（此前启动 ${STATE_COUNT[STATE_IDX]} 次）: $pattern"
                STATE_COUNT[STATE_IDX]=0
                STATE_GAVEUP[STATE_IDX]=0
            fi
            continue
        fi

        [ $STATE_IDX -ge 0 ] || new_state "$line"
        # 达到上限后不再启动，仅等待恢复；放弃日志只记一次
        if [ "${STATE_COUNT[STATE_IDX]}" -ge $MAX_START ]; then
            if [ "${STATE_GAVEUP[STATE_IDX]}" != 1 ]; then
                STATE_GAVEUP[STATE_IDX]=1
                log "已启动 $MAX_START 次仍不存在，停止启动，继续检查恢复: $pattern"
            fi
            continue
        fi
        now=$(date +%s)
        elapsed=$((now - STATE_LAST[STATE_IDX]))
        # 时钟回拨时 elapsed 为负，允许启动
        if [ $elapsed -ge 0 ] && [ $elapsed -lt "$RETRY_INTERVAL" ]; then continue; fi
        STATE_LAST[STATE_IDX]=$now
        STATE_COUNT[STATE_IDX]=$((STATE_COUNT[STATE_IDX] + 1))

        log "进程不存在，尝试启动（第 ${STATE_COUNT[STATE_IDX]}/$MAX_START 次）: $pattern"
        # 后台提交，前台命令不阻塞守护；新会话脱离终端；不继承配置与锁
        # set -m：非交互 Bash 的后台命令默认忽略 INT/QUIT，会被业务进程继承
        set -m
        setsid bash -c "$cmd" </dev/null >>"$LOG_FILE" 2>&1 200>&- &
        set +m
        log "已提交启动: $cmd"
    done <"$CONF_FILE"
}

trap 'log "watchdog 退出"; exit 0' INT TERM
log "watchdog 启动，间隔 ${INTERVAL}s，配置 $CONF_FILE"

while true; do
    check_once
    sleep "$INTERVAL"
done
