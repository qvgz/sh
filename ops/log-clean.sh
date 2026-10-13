#!/usr/bin/env bash
# 轮转目录顶层 .log 文件
# 执行可选重开命令，保留 90 天。

set -euo pipefail

log_dir=${1:-}
run_cmd=${2:-}
if (( $# < 1 || $# > 2 )) || [[ ! -d $log_dir ]]; then
    printf '用法：%s 日志目录 [重开日志命令字符串]\n' "$0" >&2; exit 2
fi
for bin in flock find date mktemp; do
    command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; exit 1; }
done
log_dir=$(cd -- "$log_dir" && pwd -P)
exec 9>"$log_dir/.log-clean.lock"
flock -n 9 || { printf '日志目录正在轮转\n' >&2; exit 1; }
backup_root=$log_dir/backup
backup_dir=$backup_root/$(date -d yesterday +%Y%m%d)
mkdir -p -- "$backup_dir"
list=$(mktemp)
trap 'rm -f -- "$list"' EXIT
find "$log_dir" -maxdepth 1 -type f -name '*.log' -print0 >"$list"
while IFS= read -r -d '' source; do
    name=${source##*/}
    target=$backup_dir/$name
    sequence=0
    while [[ -e $target || -L $target ]]; do
        (( sequence += 1 ))
        target=$backup_dir/${name%.log}.$sequence.log
    done
    mv -n -- "$source" "$target"
    # mv -n 跳过也返回成功，必须检查，避免循环或误报完成。
    [[ ! -e $source ]] || { printf '轮转失败：%s\n' "$source" >&2; exit 1; }
done <"$list"
if [[ -n $run_cmd ]]; then bash -c "$run_cmd" 9>&-; fi
find "$backup_root" -type f -name '*.log' -mtime +90 -delete
find "$backup_root" -mindepth 1 -depth -type d -empty -delete
