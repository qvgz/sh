#!/bin/bash
# Nginx 日志轮询切割
# 策略：当天只移动不压缩，下次运行时再压缩旧文件，彻底消除 IO 竞态风险。

set -euo pipefail

# --- 配置区域 ---
LOG_DIR="/var/log/nginx"
BACKUP_DIR="${LOG_DIR}/history"
RETENTION_DAYS=30
# 获取昨天的日期作为本次切割日志的后缀 (例如: 20231027)
YESTERDAY=$(date -d "yesterday" +%Y%m%d)

# 核心指令配置
# 场景 A: Docker 环境 (默认)
NGINX_CMD=(docker exec nginx-server nginx -s reopen)
# 场景 B: 本地环境
# NGINX_CMD=(/usr/local/nginx/sbin/nginx -s reopen)

# --- 0. 环境自检 ---
if [ ! -d "$LOG_DIR" ]; then
    echo "Error: Log directory $LOG_DIR does not exist."
    exit 1
fi
mkdir -p "$BACKUP_DIR"

# --- 1. 日志迁移 (Move) ---
# 移动当前日志到备份目录，命名为 access_20231027.log
count=$(find "$LOG_DIR" -maxdepth 1 -name "*.log" | wc -l)
if [ "$count" -eq 0 ]; then
    echo "No log files found in $LOG_DIR, skipping."
    exit 0
fi

find "$LOG_DIR" -maxdepth 1 -name "*.log" | while read -r log_file; do
    filename=$(basename "$log_file")
    target="$BACKUP_DIR/${filename%.*}_${YESTERDAY}.log"
    mv "$log_file" "$target"
done

# --- 2. 信号通知 (Signal) ---
if ! "${NGINX_CMD[@]}"; then
    echo "Error: Failed to reload Nginx. Logs are moved but not rotated."
    exit 1
fi

# --- 3. 延迟压缩 (Delay Compress) ---
# 逻辑：进入备份目录，压缩所有 .log 文件，但排除掉后缀为 ${YESTERDAY}.log 的文件。
# 这样不仅压缩了"前天"的日志，也能自动补压因为脚本报错而漏压的历史日志。

cd "$BACKUP_DIR"

find . -maxdepth 1 \
    -type f \
    -name "*.log" \
    ! -name "*_${YESTERDAY}.log" \
    -exec gzip {} +

# --- 4. 清理 (Cleanup) ---
# 清理超过保留时间的 .gz 文件
find . -maxdepth 1 -name "*.gz" -mtime +$RETENTION_DAYS -delete
