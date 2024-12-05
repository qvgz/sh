#!/bin/bash
# 进程守护
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/daemon.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/daemon.sh)"

# 配置项
LOG_FILE="/var/log/daemon.log"
CHECK_INTERVAL=3                   # 检查间隔(秒)
RESTART_INTERVAL=20                # 重启间隔(秒)
MAX_RESTART=3                      # 最大重启次数
RESTART_COUNT=0                    # 重启计数器
LAST_RESTART_TIME=0                # 上次重启时间

# 检查参数
if [ $# -lt 1 ]; then
    echo "使用方法: $0 <程序路径> [程序参数...]"
    echo "示例: $0 /usr/local/bin/myapp -c config.ini"
    exit 1
fi

# 重启间隔(秒)
if [ $RESTART_INTERVAL -lt $((CHECK_INTERVAL*MAX_RESTART+2*MAX_RESTART)) ]; then              
    echo "不符合 重启间隔 > (检查间隔+2)*MAX_RESTART"
    exit 1
fi

PROCESS_PATH="$1"
shift
PROCESS_ARGS="$*"

# 确保日志文件存在
touch $LOG_FILE

# 日志函数
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $PROCESS_PATH $PROCESS_ARGS $1" >> $LOG_FILE
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $PROCESS_PATH $PROCESS_ARGS $1"
}

# 检查程序是否存在
if [ ! -f "$PROCESS_PATH" ]; then
    log_message "错误: 程序不存在"
    exit 1
fi

# 检查程序是否有执行权限
if [ ! -x "$PROCESS_PATH" ]; then
    log_message "错误: 程序没有执行权限"
    exit 1
fi

# 获取进程PID
get_pid() {
    pidof "$PROCESS_PATH"
}

# 检查进程是否运行
is_process_running() {
    if [ -n "$(get_pid)" ]; then
        return 0
    else
        return 1
    fi
}

# 启动进程
start_process() {
    log_message "正在启动进程"
    cd "$(dirname $PROCESS_PATH)"
    (
        nohup "${PROCESS_PATH}" ${PROCESS_ARGS} >/dev/null 2>&1 &
    )
    sleep 3
    
    if is_process_running; then
        log_message "进程启动成功 (PID: $(get_pid))"
        RESTART_COUNT=0
        return 0
    else
        log_message "进程启动失败"
        return 1
    fi
}

# 检查是否可以重启
can_restart() {
    current_time="$(date +%s)"
    
    # 如果距离上次重启时间超过重启间隔，重置计数器
    if [ $((current_time - LAST_RESTART_TIME)) -gt $RESTART_INTERVAL ]; then
        RESTART_COUNT=0
    fi
    
    # 检查是否超过最大重启次数
    if [ $RESTART_COUNT -ge $MAX_RESTART ]; then
        log_message "警告: 已达到最大重启次数 ($MAX_RESTART)"
        return 1
    fi
    
    return 0
}

# 重启进程
restart_process() {
    RESTART_COUNT=$((RESTART_COUNT + 1))
    LAST_RESTART_TIME=$(date +%s)
    
    log_message "正在重启进程 (第 $RESTART_COUNT 次尝试)"
    start_process
}

# 主循环
log_message "进程守护启动"
start_process

while true; do
    if ! is_process_running; then
        log_message "检测到进程已停止"
        
        if can_restart; then
            restart_process
        else
            log_message "错误: 进程重启失败次数过多，退出守护程序"
            exit 1
        fi
    fi
    
    sleep $CHECK_INTERVAL
done

