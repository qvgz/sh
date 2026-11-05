#!/usr/bin/env bash
# 备份目录顶层 .log 文件：压缩复制到 backup/昨日YYYYMMDD/ 后清空原文件，
# 执行可选重开命令，按备份日期删除过期备份；-t 只清空不备份。

set -euo pipefail

usage() {
    printf '用法：%s [-k 保留天数，默认 90] [-t 只清空不备份] 日志目录 [重开日志命令字符串]\n' "$0" >&2
    exit 2
}

keep_days=90
truncate_only=0
while getopts ':k:t' opt; do
    case $opt in
        k) keep_days=$OPTARG ;;
        t) truncate_only=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
(( $# >= 1 && $# <= 2 )) || usage
[[ $keep_days =~ ^[1-9][0-9]*$ ]] || usage
[[ -d $1 ]] || usage
reopen_cmd=${2:-}
# 选项须在日志目录前，防止 `目录 -t` 中的 -t 被当作重开命令
[[ $reopen_cmd != -* ]] || usage

for bin in flock find date gzip truncate mktemp; do
    command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; exit 1; }
done

log_dir=$(cd -- "$1" && pwd -P)
exec 9>"$log_dir/.log-clean.lock"
flock -n 9 || { printf '日志目录正在轮转：%s\n' "$log_dir" >&2; exit 1; }

backup_root=$log_dir/backup
backup_dir=$backup_root/$(date -d yesterday +%Y%m%d)
# 提前计算，保留天数过大时在改动文件前失败
cutoff=$(date -d "$keep_days days ago" +%Y%m%d)
rc=0

# 1. 压缩复制顶层非空普通 .log 文件（不含符号链接、空文件），成功后清空原文件；-t 时直接清空
# 先写入临时文件：find 失败由 set -e 捕获（Bash 4.2 无 mapfile -d）
list=$(mktemp)
trap 'rm -f -- "$list"' EXIT
find "$log_dir" -maxdepth 1 -type f -name '*.log' -size +0 -print0 >"$list"
if [[ -s $list ]]; then
    ((truncate_only)) || mkdir -p -- "$backup_dir"
    while IFS= read -r -d '' source; do
        if ((truncate_only)); then
            truncate -c -s 0 -- "$source"
            continue
        fi
        name=${source##*/}
        target=$backup_dir/$name.gz
        seq=0
        # 同名已存在时依次加序号，不覆盖
        while [[ -e $target || -L $target ]]; do
            seq=$((seq + 1))
            target=$backup_dir/${name%.log}.$seq.log.gz
        done
        # 先写临时文件再改名，中断时不留下看似完整的 .gz；失败不清空原文件
        gzip -c -- "$source" >"$target.tmp" || { rm -f -- "$target.tmp"; exit 1; }
        mv -f -- "$target.tmp" "$target"
        # 复制结束到清空之间写入的行不进备份
        truncate -c -s 0 -- "$source"
    done <"$list"

    # 2. 重开日志：失败只影响退出码，备份已完成，继续清理
    if [[ -n $reopen_cmd ]]; then
        bash -c "$reopen_cmd" 9>&- || { rc=$?; printf '重开命令失败：%s\n' "$rc" >&2; }
    fi
fi

# 3. 按目录名日期删除过期备份：早于今天减保留天数的 YYYYMMDD 目录整个删除；
#    非日期目录、符号链接不动
for dir in "$backup_root"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]; do
    [[ -d $dir && ! -L $dir ]] || continue
    if [[ ${dir##*/} < $cutoff ]]; then rm -rf -- "$dir"; fi
done

exit "$rc"
