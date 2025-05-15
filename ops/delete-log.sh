#!/bin/bash
# 删除日志
# $1 日志路径
# $2 删除日志后需要执行的命令
# $3 日志保留天数
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/delete-log.sh.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/delete-log.sh.sh)"

set -e

log_dir=$1
run_cmd=$2
save_day="${3:-90}"
log_dir_bakcup="${log_dir}/backup/$(date -d "yesterday" +%Y%m%d)"

[ -z "$log_dir" ] && exit 1
mkdir -p $log_dir_bakcup && find $log_dir -maxdepth 1 -type f -name '*.log' -exec mv -t $log_dir_bakcup -- {} +

[ -z "$run_cmd" ] || eval "$run_cmd"

find $log_dir_bakcup -type f -mtime +${save_day} -name '*.log' -delete
find $log_dir_bakcup -depth -type d -empty -delete