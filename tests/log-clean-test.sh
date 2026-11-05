#!/usr/bin/env bash
# log-clean.sh 测试，需 Linux（最低 CentOS 7.9：Bash 4.2、GNU date/find/truncate、flock、gzip）
set -uo pipefail

script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/ops/log-clean.sh"
t=$(mktemp -d)
trap 'chmod -R u+w -- "$t" 2>/dev/null; rm -rf -- "$t"' EXIT
failures=0
y=$(date -d yesterday +%Y%m%d)
d100=$(date -d '100 days ago' +%Y%m%d)

check() {
    local name=$1 want=$2 got=$3
    if [[ $got == "$want" ]]; then echo "ok   $name"; else
        echo "FAIL $name"; diff <(echo "$want") <(echo "$got"); failures=$((failures + 1)); fi
}
yes_if() { if "$@"; then echo yes; else echo no; fi; }
# 列出目录下所有文件（相对路径，排序）；普通文件附大小
tree_of() { (cd -- "$1" && find . -mindepth 1 ! -name .log-clean.lock \( -type f -printf '%p %s\n' -o -printf '%p\n' \) | LC_ALL=C sort); }

# 参数校验
bash "$script" 2>/dev/null; check "无参数返回 2" 2 $?
bash "$script" "$t/none" 2>/dev/null; check "目录不存在返回 2" 2 $?
bash "$script" -k 0 "$t" 2>/dev/null; check "保留天数 0 返回 2" 2 $?
bash "$script" -k x "$t" 2>/dev/null; check "保留天数非数字返回 2" 2 $?
bash "$script" "$t" cmd extra 2>/dev/null; check "多余参数返回 2" 2 $?
d=$t/opt; mkdir -p "$d"; echo a >"$d/a.log"
bash "$script" "$d" -t 2>/dev/null; check "选项在目录后返回 2" 2 $?
bash "$script" -k 999999999999 "$d" 2>/dev/null; check "保留天数过大返回 1" 1 $?
check "参数错误不改动文件" "a|no" "$(cat "$d/a.log")|$(yes_if test -e "$d/backup")"

# 压缩复制、清空原文件、重名序号、空文件、符号链接、子目录、过期目录、非日期目录
d=$t/app
mkdir -p "$d/sub" "$d/backup/$y" "$d/backup/$d100" "$d/backup/keep"
echo a >"$d/a.log"; echo b >"$d/b.log"; echo c >"$d/sub/c.log"; echo x >"$d/x.txt"; : >"$d/z.log"
ln -s "$d/x.txt" "$d/l.log"
echo old | gzip >"$d/backup/$y/a.log.gz"
echo e >"$d/backup/$d100/e.log.gz"
echo k >"$d/backup/keep/k.log"; touch -d '200 days ago' "$d/backup/keep/k.log"
bash "$script" "$d" "[[ ! -s '$d/a.log' && -f '$d/backup/$y/b.log.gz' ]] && touch '$t/reopened'"
check "正常返回 0" 0 $?
check "重开命令在清空后执行" yes "$(yes_if test -f "$t/reopened")"
check "目录结构" "$(LC_ALL=C sort <<EOT
./a.log 0
./b.log 0
./backup
./backup/$y
./backup/$y/a.1.log.gz $(stat -c %s "$d/backup/$y/a.1.log.gz")
./backup/$y/a.log.gz $(stat -c %s "$d/backup/$y/a.log.gz")
./backup/$y/b.log.gz $(stat -c %s "$d/backup/$y/b.log.gz")
./backup/keep
./backup/keep/k.log 2
./l.log
./sub
./sub/c.log 2
./x.txt 2
./z.log 0
EOT
)" "$(tree_of "$d")"
check "新备份内容" a "$(gzip -dc "$d/backup/$y/a.1.log.gz")"
check "旧备份未覆盖" old "$(gzip -dc "$d/backup/$y/a.log.gz")"

# 追加模式写入：清空后从文件头继续写，无空洞
d=$t/append; mkdir -p "$d"
exec 7>>"$d/w.log"; echo before >&7
bash "$script" "$d"; check "追加写入返回 0" 0 $?
echo after >&7; exec 7>&-
check "清空后追加写入" after "$(cat "$d/w.log")"
check "追加写入备份" before "$(gzip -dc "$d/backup/$y/w.log.gz")"

# 保留天数参数：按目录名日期
d=$t/keep; mkdir -p "$d/backup/$d100"; echo f >"$d/backup/$d100/f.log.gz"
bash "$script" -k 200 "$d"; check "-k 200 返回 0" 0 $?
check "-k 200 保留 100 天前目录" yes "$(yes_if test -f "$d/backup/$d100/f.log.gz")"
bash "$script" -k 99 "$d"; check "-k 99 返回 0" 0 $?
check "-k 99 删除 100 天前目录" no "$(yes_if test -e "$d/backup/$d100")"

# -t 只清空不备份：不建当日备份目录，重开与过期清理照常
d=$t/trunc; mkdir -p "$d/backup/$d100"; echo a >"$d/a.log"; echo b >"$d/b.txt"
bash "$script" -t "$d" "touch '$t/trunc-reopened'"; check "-t 返回 0" 0 $?
check "-t 清空 .log" 0 "$(stat -c %s "$d/a.log")"
check "-t 不动非 .log" b "$(cat "$d/b.txt")"
check "-t 不建备份" no "$(yes_if test -e "$d/backup/$y")"
check "-t 执行重开" yes "$(yes_if test -f "$t/trunc-reopened")"
check "-t 清理过期" no "$(yes_if test -e "$d/backup/$d100")"
bash "$script" -t -x "$d" 2>/dev/null; check "未知选项返回 2" 2 $?

# 重开失败：返回其退出码，备份与清理照常
d=$t/fail; mkdir -p "$d/backup/$d100"; echo a >"$d/a.log"
bash "$script" "$d" 'exit 3' 2>/dev/null; check "重开失败返回 3" 3 $?
check "重开失败已备份并清空" yes "$(yes_if test -f "$d/backup/$y/a.log.gz" -a ! -s "$d/a.log")"
check "重开失败仍清理过期" no "$(yes_if test -e "$d/backup/$d100")"

# 无非空 .log 时不执行重开命令
d=$t/empty; mkdir -p "$d"; : >"$d/e.log"
bash "$script" "$d" "touch '$t/empty-reopened'"; check "无日志返回 0" 0 $?
check "无日志不执行重开" no "$(yes_if test -e "$t/empty-reopened")"
check "无日志不建 backup" no "$(yes_if test -e "$d/backup")"

# 重开命令不继承锁
d=$t/lock; mkdir -p "$d"; echo a >"$d/a.log"
bash "$script" "$d" '[[ ! -e /proc/self/fd/9 ]]'; check "重开命令不继承锁 fd" 0 $?

# 权限相关（root 不受权限限制，跳过）
if ((EUID != 0)); then
    # 备份目录不可写：gzip 失败返回 1，不清空原文件、不重开、不留临时文件
    d=$t/rofail; mkdir -p "$d/backup/$y"; echo a >"$d/a.log"; chmod 555 "$d/backup/$y"
    bash "$script" "$d" "touch '$t/rofail-reopened'" 2>/dev/null; check "压缩失败返回 1" 1 $?
    check "压缩失败不清空原文件" a "$(cat "$d/a.log")"
    check "压缩失败不执行重开" no "$(yes_if test -e "$t/rofail-reopened")"
    check "压缩失败无残留" "" "$(ls "$d/backup/$y")"
    chmod 755 "$d/backup/$y"

    # 目录不可读：find 失败返回 1
    d=$t/noread; mkdir -p "$d"; echo a >"$d/a.log"; chmod 300 "$d"
    bash "$script" "$d" 2>/dev/null; check "目录不可读返回 1" 1 $?
    chmod 700 "$d"
fi

# 锁冲突
d=$t/lock
exec 8>"$d/.log-clean.lock"; flock -n 8
bash "$script" "$d" 2>/dev/null; check "锁冲突返回 1" 1 $?
exec 8>&-

if ((failures > 0)); then echo "失败 $failures 项"; exit 1; fi
echo "全部通过"
