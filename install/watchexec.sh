#!/bin/bash
# 安装 watchexec
# https://github.com/watchexec/watchexec/
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/watchexec.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/install/watchexec.sh)"

set -euo pipefail

# 1. 架构检测
arch=""
case "$(uname -m)" in
    x86_64) arch="x86_64-unknown-linux-musl" ;;
    *)
        echo "Error:不支持的架构: $(uname -m)" >&2
        exit 1
        ;;
esac

# 2. 获取最新版本号
# GitHub API 返回的 tag_name 通常带 "v" (如 v1.25.1)，我们需要去除 v 用于拼接下载链接
# 但下载文件名中通常包含版本号
latest_tag=$(curl -s "https://api.github.com/repos/watchexec/watchexec/releases/latest" | \
                grep '"tag_name":' | \
                sed -E 's/.*"([^"]+)".*/\1/')

# 提取纯数字版本号 (例如 v1.23.0 -> 1.23.0)
latest_ver="${latest_tag#v}"

if [[ -z "$latest_ver" ]]; then
    echo "Error: 无法获取最新版本信息" >&2
    exit 1
fi

# 3. 获取本地版本 (容错处理：若未安装则设为 0)
_ver="0"
if command -v watchexec >/dev/null 2>&1; then
    # watchexec --version 输出示例: "watchexec 1.23.0"
    _ver=$(watchexec --version | awk '{print $2}')
fi

# 4. 版本比对与安装
if [[ "$_ver" != "$latest_ver" ]]; then
    echo "发现新版本: ${latest_ver} (当前: ${_ver})，正在安装..."

    # 构造下载链接 (使用 musl 静态编译版以获得最佳兼容性)
    download_url="https://github.com/watchexec/watchexec/releases/download/${latest_tag}/watchexec-${latest_ver}-${arch}.tar.xz"

    # 流式解压安装：curl -> tar -> install
    # -L: 跟随重定向
    # tar --strip-components=1: 去除解压后的顶层目录
    # -O: 提取特定文件到标准输出
    curl -L --fail --progress-bar "$download_url" | \
        tar -xJ -O --wildcards "*/watchexec" | \
        sudo tee /usr/bin/watchexec >/dev/null

    sudo chmod +x /usr/bin/watchexec

    echo "安装完成: $(watchexec --version)"
else
    echo "已是最新版本 ($_ver)，无需更新。"
fi
