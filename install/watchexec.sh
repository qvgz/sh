#!/usr/bin/env bash
# linux 安装 watchexec gun 版本
# https://github.com/watchexec/watchexec/tree/main
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/watchexec.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/install/watchexec.sh)"

set -e

local_version=$(watchexec --version | grep release | awk '{print $2}')
latest_version=$(curl --silent "https://api.github.com/repos/watchexec/watchexec/releases/latest" | jq -r .tag_name | sed 's/^.//')

if [[ "$local_version" != "$latest_version" ]];then
    curl -SL https://github.com/watchexec/watchexec/releases/download/v${latest_version}/watchexec-${latest_version}-x86_64-unknown-linux-gnu.tar.xz -o /tmp/watchexec-${latest_version}-x86_64-unknown-linux-gnu.tar.xz

    tar -xf /tmp/watchexec-${latest_version}-x86_64-unknown-linux-gnu.tar.xz -O watchexec-${latest_version}-x86_64-unknown-linux-gnu/watchexec | sudo tee /usr/local/bin/watchexec > /dev/null

    sudo chmod +x /usr/local/bin/watchexec
fi
