#!/usr/bin/env bash
# Nginx 日志轮询切割
# 策略：当天只移动不压缩，下次运行时再压缩旧文件，减少 IO 竞态风险。

set -euo pipefail

LOG_DIR="/var/log/nginx"
BACKUP_DIR="${LOG_DIR}/history"
RETENTION_DAYS=30
YESTERDAY="$(date -d "yesterday" +%Y%m%d)"

# 场景 A: Docker 环境 (默认)
NGINX_CMD=(docker exec nginx-server nginx -s reopen)
# 场景 B: 本地环境
# NGINX_CMD=(/usr/local/nginx/sbin/nginx -s reopen)

# 0) 环境自检
if [[ ! -d "$LOG_DIR" ]]; then
  echo "Error: Log directory $LOG_DIR does not exist." >&2
  exit 1
fi
mkdir -p "$BACKUP_DIR"

# 1) 是否存在日志文件（快速判断）
if ! find "$LOG_DIR" -maxdepth 1 -type f -name "*.log" -print -quit | grep -q .; then
  echo "No log files found in $LOG_DIR, skipping."
  exit 0
fi

# 2) 先做一次 reopen 探测（失败则不移动，避免 nginx 写入被移动文件）
if ! "${NGINX_CMD[@]}"; then
  echo "Error: Failed to reopen Nginx logs. Aborting rotate to avoid moving active log files." >&2
  exit 1
fi

# 3) 日志迁移 (Move)
# 移动当前日志到备份目录，命名为 access_YYYYMMDD.log
while IFS= read -r -d '' log_file; do
  filename="$(basename "$log_file")"
  target="$BACKUP_DIR/${filename%.*}_${YESTERDAY}.log"
  mv -- "$log_file" "$target"
done < <(find "$LOG_DIR" -maxdepth 1 -type f -name "*.log" -print0)

# 4) 再次 reopen，让 nginx 打开新的 $LOG_DIR/*.log
if ! "${NGINX_CMD[@]}"; then
  echo "Error: Failed to reopen Nginx after moving logs. Current logging may continue in moved files." >&2
  exit 1
fi

# 5) 延迟压缩：压缩除“昨天后缀”的所有 .log（补压历史漏压）
cd "$BACKUP_DIR"
find . -maxdepth 1 -type f -name "*.log" ! -name "*_${YESTERDAY}.log" -exec gzip -- {} +

# 6) 清理：清理超过保留时间的 .gz
find . -maxdepth 1 -type f -name "*.gz" -mtime +"$RETENTION_DAYS" -delete
