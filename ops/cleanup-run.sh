#!/usr/bin/env bash
# 脚本停止/终端关闭时进程终止
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/cleanup-run.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/cleanup-run.sh)"

set -euo pipefail

(($#)) || {
  printf 'Usage: %s command [args ...]\n' "${0##*/}" >&2
  exit 64
}

pid=

cleanup() {
  local ec=$?
  trap - EXIT HUP INT TERM

  [[ ${pid-} ]] || exit "$ec"

  kill "$pid" 2>/dev/null || exit "$ec"

  for _ in 1 2 3 4 5; do
    kill -0 "$pid" 2>/dev/null || exit "$ec"
    sleep 0.1
  done

  kill -KILL "$pid" 2>/dev/null || true
  exit "$ec"
}

trap cleanup EXIT HUP INT TERM

"$@" &
pid=$!
wait "$pid"
