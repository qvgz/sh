#!/bin/bash
# 进程守护

# 检查间隔（秒）
INTERVAL=10

# 同一进程重启的最短间隔（秒）
RETRY_INTERVAL=30

# 脚本目录及日志
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/watchdog.log"
LOCK_FILE="$SCRIPT_DIR/watchdog.lock"

# ==========================================
# 进程配置：进程匹配字符串|重启命令
# 可配置 1~N 个进程
# ==========================================
PROCESSES=(
    ""
)

# 检查依赖
for cmd in pgrep flock date sleep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "缺少命令: $cmd" >&2
        exit 1
    fi
done

# 防止守护脚本重复运行
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "watchdog 已在运行"
    exit 1
fi

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# 记录每个进程上次重启时间
LAST_RESTART=()

log "watchdog 启动，监控 ${#PROCESSES[@]} 个进程"

while true; do
    i=0

    for item in "${PROCESSES[@]}"; do
        # 解析进程配置
        process="${item%%|*}"
        restart_cmd="${item#*|}"

        # 检查进程是否存在
        if ! pgrep -f -- "$process" >/dev/null 2>&1; then
            now=$(date +%s)
            last=${LAST_RESTART[i]:-0}

            # 防止频繁重启
            if (( now - last >= RETRY_INTERVAL )); then
                LAST_RESTART[i]=$now

                log "进程不存在: $process"
                log "执行重启: $restart_cmd"

                # 执行重启，关闭子进程继承的文件锁
                bash -c "$restart_cmd" 200>&- >> "$LOG_FILE" 2>&1
                ret=$?

                if (( ret == 0 )); then
                    log "重启命令执行成功: $process"
                else
                    log "重启命令执行失败: $process, code=$ret"
                fi
            fi
        fi

        i=$((i + 1))
    done

    sleep "$INTERVAL"
done
