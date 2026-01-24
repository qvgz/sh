#!/usr/bin/env bash
# 文件目录变更执行命令
# https://github.com/watchexec/watchexec/
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/wexec.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/wexec.sh)"

set -euo pipefail

# 1. 依赖检查 (Fail Fast)
if ! command -v watchexec &> /dev/null; then
    echo "Error: 未找到 'watchexec' 命令，请先安装。" >&2
    exit 1
fi

# 2. 参数校验
if [[ $# -eq 0 ]]; then
    echo "Usage: ./wexec.sh <your_command>" >&2
    echo "Example: ./wexec.sh ls" >&2
    exit 1
fi

# 3. 执行监控逻辑
# -r (--restart): 文件变更时，强制杀掉当前正在运行的进程并重启 (开发服务器常用)
# -c (--clear)  : 重启前清空屏幕 (提升开发体验)
# -p (--postpone): 启动时不立即执行，等待第一次文件变更
# --debounce 1s: 防抖动 1s
# -- "$@": 传递原始参数数组，确保含空格或引号的命令能正确解析
watchexec -r -c -p --debounce 1s -- "$@"
