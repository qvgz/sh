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

move_log() {
  local source="$1"
  local file_name="${source##*/}"
  local name="${file_name%.log}"
  local target="$backup_dir/$file_name"
  local sequence=0

  while [[ -e "$source" ]]; do
    while [[ -e "$target" || -L "$target" ]]; do
      ((sequence += 1))
      target="$backup_dir/$name.$sequence.log"
    done

    # -n also protects against another process creating target after the check.
    mv -n -- "$source" "$target"
  done
}

# 备份当前日志
while IFS= read -r -d '' log_file; do
  move_log "$log_file"
done < <(find "$log_dir" \
  -maxdepth 1 \
  -type f \
  -name '*.log' \
  -print0)

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
