#!/usr/bin/env bash
# linux x86_64 安装 docker-compose
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/docker-compose.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/install/docker-compose.sh)"

set -e

local_version="$(docker compose version)"
latest_version="$(curl --silent "https://api.github.com/repos/docker/compose/releases/latest" | jq -r .tag_name)"

if [[ "$local_version" != "$latest_version" ]];then
    sudo mkdir -p /usr/local/lib/docker/cli-plugins/
    sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi


