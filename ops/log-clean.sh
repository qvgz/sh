#!/usr/bin/env bash
# 日志清理备份
# $1 日志路径
# $2 日志处理后需要执行命令

set -Eeuo pipefail

# 保留日志天数
backup_day="90"
# 命令测试
run_cmd_test=false

log_dir="${1:-}"
run_cmd="${2:-}"

if [[ ! -d "$log_dir" ]]; then
  echo "Error: Log directory $log_dir does not exist." >&2
  exit 1
fi

backup_root="$log_dir/backup"
backup_dir="$backup_root/$(date -d "yesterday" +%Y%m%d)"

if [[ -n "$run_cmd" && "$run_cmd_test" == true ]]; then
  bash -c "$run_cmd"
fi

mkdir -p "$backup_dir"

# 备份当前日志
find "$log_dir" \
  -maxdepth 1 \
  -type f \
  -name '*.log' \
  -exec mv -- {} "$backup_dir/" \;

if [[ -n "$run_cmd" ]]; then
  bash -c "$run_cmd"
fi

# 删除超过保留天数的备份日志
ionice -c3 find "$backup_root" \
  -type f \
  -name '*.log' \
  -mtime +"$backup_day" \
  -delete

# 删除空目录，但保留 backup 根目录
find "$backup_root" \
  -mindepth 1 \
  -depth \
  -type d \
  -empty \
  -delete
