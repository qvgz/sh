#!/usr/bin/env bash
# centos debian 安装 docker
# 国内 腾讯源 七牛 Docker Hub 镜像
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/docker-centos-debian.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/install/docker-centos-debian.sh)"

set -e

# debian 安装
# https://docs.docker.com/engine/install/debian/#uninstall-docker-engine
function debian_install(){
  (sudo apt remove docker.io docker-doc docker-compose podman-docker containerd runc || exit 0)

  sudo apt update
  sudo apt install -y ca-certificates curl gnupg

  sys_version=$(grep -w 'VERSION_CODENAME' /etc/os-release | awk -F '=' '{print $2}')

  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://${mirrors}/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://${mirrors}/linux/debian \
    ${sys_version} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# centos 安装
# https://docs.docker.com/engine/install/centos/
function centos_install(){
  (
    sudo sudo yum remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || exit 0
  )

  sudo yum install -y yum-utils
  sudo yum-config-manager --add-repo https://${mirrors}/linux/centos/docker-ce.repo
  sudo yum makecache fast && sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

mirrors="download.docker.com"
docker_daemon="https://raw.githubusercontent.com/qvgz/sh/master/file/docker-daemon.json"
if ! ping -c 1 google.com &> /dev/null ;then
  mirrors="mirrors.cloud.tencent.com/docker-ce"
  docker_daemon="https://proxy.qvgz.org/sh/file/docker-daemon-cn.json"
fi

# 版本选择
case $(grep -w ID /etc/os-release | awk -F '=' '{print $2}' | sed 's/"//g') in
  debian)
    debian_install
    ;;
  centos)
    centos_install
    ;;
  *)
    echo "退出！系统不支持"
    exit 1
    ;;
esac


# docker 配置
sudo mkdir -p /etc/docker
sudo curl -o /etc/docker/daemon.json $docker_daemon

# 非root 用户加入 docker 用户组
if [[ $(id -u) != "0" ]]; then
    sudo usermod -aG docker $USER
    newgrp docker
fi

sudo systemctl enable --now docker
