#!/usr/bin/env bash
# 退出时清理运行的子进程（整个进程组）

set -uo pipefail
(( $# )) || { printf '用法：%s command [args ...]\n' "$0" >&2; exit 2; }

grace=${CLEANUP_RUN_GRACE:-0.5}
[[ $grace =~ ^([0-9]+)(\.([0-9]))?$ ]] || {
    printf 'CLEANUP_RUN_GRACE 须为秒数，最多 1 位小数：%s\n' "$grace" >&2
    exit 2
}
ticks=$(( 10#${BASH_REMATCH[1]} * 10 + 10#${BASH_REMATCH[3]:-0} ))

pid=''
# $1：收到的信号；为空表示子命令已自行结束。
cleanup() {
    local status=$? sig=${1:-TERM} i
    trap - EXIT HUP INT TERM
    if [[ -n $pid ]]; then
        if kill -"$sig" -- "-$pid" 2>/dev/null; then
            # 唤醒已停止的进程，使其能处理信号。
            kill -CONT -- "-$pid" 2>/dev/null
            for (( i = 0; i < ticks; i++ )); do
                kill -0 -- "-$pid" 2>/dev/null || break
                sleep 0.1
            done
            kill -KILL -- "-$pid" 2>/dev/null
        fi
        wait "$pid" 2>/dev/null
    fi
    # 以同一信号结束自身，调用方可识别为被信号终止。
    [[ -z ${1:-} ]] || kill -"$1" "$$"
    exit "$status"
}
trap cleanup EXIT
for s in HUP INT TERM; do
    # shellcheck disable=SC2064 # 有意立即展开信号名
    trap "cleanup $s" "$s"
done

# 作业控制使后台命令拥有独立进程组。
set -m
# 后台进程组读终端会被 SIGTTIN 挂起，改为读 /dev/null。
if [[ -t 0 ]]; then
    "$@" </dev/null &
else
    "$@" &
fi
pid=$!
wait "$pid"
