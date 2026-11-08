#!/usr/bin/env bash
# 监控文件新增行，匹配字符串（支持 * ? 通配）在时间窗口内达到次数时执行命令，带抑制时间，最低兼容 CentOS 7.9

set -uo pipefail

# 必须：监控文件、匹配字符串、触发命令
FILE=${FILE:-}
PATTERN=${PATTERN:-}
CMD=${CMD:-}
# 可选：窗口内命中多少次算一次触发；计数窗口（秒，0 不清零）；两次执行命令的最短间隔（秒）
HITS=${HITS:-1}
WINDOW=${WINDOW:-60}
SUPPRESS=${SUPPRESS:-60}
# 可选：命令执行超时（秒，0 不限制），超时发 TERM，5 秒后仍未退出发 KILL
TIMEOUT=${TIMEOUT:-60}
# 可选：日志时区，命令同样继承
export TZ=${TZ:-Asia/Shanghai}

die() { printf '错误: %s\n' "$*" >&2; exit 2; }

[[ -n $FILE ]] || die "FILE 未设置"
[[ -n $PATTERN ]] || die "PATTERN 未设置"
# grep 会把换行拆成多个模式，空行模式匹配所有行
[[ $PATTERN != *$'\n'* ]] || die "PATTERN 不能含换行"
[[ -n $CMD ]] || die "CMD 未设置"
[[ $HITS =~ ^[1-9][0-9]{0,8}$ ]] || die "HITS 须为正整数: $HITS"
[[ $WINDOW =~ ^(0|[1-9][0-9]{0,8})$ ]] || die "WINDOW 须为非负整数: $WINDOW"
[[ $SUPPRESS =~ ^(0|[1-9][0-9]{0,8})$ ]] || die "SUPPRESS 须为非负整数: $SUPPRESS"
[[ $TIMEOUT =~ ^(0|[1-9][0-9]{0,8})$ ]] || die "TIMEOUT 须为非负整数: $TIMEOUT"

# 通配转 grep 基本正则：转义 \ . [ ] ^ $，* → .*，? → .
re=$(printf '%s' "$PATTERN" | sed 's/[][\.^$]/\\&/g; s/\*/.*/g; s/?/./g')

# 后台执行命令，结束后一次输出：触发时间、匹配行、结果；失败附完整输出
run() {
    local out rc
    out=$(MATCH_LINE=$2 timeout -k 5 "$TIMEOUT" bash -c "$CMD" 2>&1 </dev/null)
    rc=$?
    if ((rc == 0)); then
        printf '[%s] 匹配: %s | 执行成功\n' "$1" "$2"
    elif ((TIMEOUT > 0 && (rc == 124 || rc == 137))); then
        printf '[%s] 匹配: %s | 执行超时 %ss rc=%d\n%s\n' "$1" "$2" "$TIMEOUT" "$rc" "$out"
    else
        printf '[%s] 匹配: %s | 执行失败 rc=%d\n%s\n' "$1" "$2" "$rc" "$out"
    fi
}

count=0 start=0 last=-1
# --pid：本脚本退出后 tail 随之退出，不残留
while IFS= read -r line; do
    printf -v now '%(%s)T' -1
    # 窗口从首次命中开始，过期后清零重新计数；时钟回拨视为过期
    if ((count == 0 || now < start || (WINDOW > 0 && now - start >= WINDOW))); then
        count=0 start=$now
    fi
    count=$((count + 1))
    ((count >= HITS)) || continue
    count=0
    # 时钟回拨时不抑制
    ((last >= 0 && now >= last && now - last < SUPPRESS)) && continue
    last=$now
    run "$(printf '%(%F %T)T' "$now")" "$line" &
# LC_ALL=C：按字节匹配，非 UTF-8（如 GBK）内容不影响 * 匹配
done < <(tail -n0 -F --pid=$$ -- "$FILE" | LC_ALL=C grep -a --line-buffered -e "$re")
# 正常不会到达：tail 异常退出时返回非 0，便于 systemd 等感知
die "tail 已退出，监控结束: $FILE"
