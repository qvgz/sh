#!/usr/bin/env bash
# 退出时清理运行的子进程

set -uo pipefail
(( $# )) || { printf '用法：%s command [args ...]\n' "$0" >&2; exit 2; }
pid=''
cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM
    if [[ -n $pid ]]; then
        kill -TERM -- "-$pid" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            kill -0 -- "-$pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL -- "-$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
# 启用作业控制，让后台命令拥有独立进程组。
set -m
"$@" &
pid=$!
wait "$pid"
