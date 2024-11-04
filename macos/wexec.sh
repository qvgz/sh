#!/usr/bin/env bash
# 文件目录变更执行脚本
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/macos/wexec.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/macos/wexec.sh)"

set -e

cd "$(pwd)"

if [[ "$*" == "" ]];then
    echo "命令为空"
    exit 1
fi

watchexec -p --delay-run 1 "$*"
