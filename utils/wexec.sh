#!/usr/bin/env bash
# 当前目录变更时执行命令
# 首次变更前不执行

(( $# )) || { printf '用法：%s command [args ...]\n' "$0" >&2; exit 2; }
command -v watchexec >/dev/null || { printf '缺少命令：watchexec\n' >&2; exit 1; }
exec watchexec -r -c -p --debounce 1s -- "$@"
