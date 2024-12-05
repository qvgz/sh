#!/bin/bash
# 安装 docker
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/docker.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/install/docker.sh)"

set -ex

# debian
# https://docs.docker.com/engine/install/debian/#uninstall-docker-engine
function debian_install(){
  (
    sudo apt remove docker.io docker-doc docker-compose podman-docker containerd runc || exit 0
  )

  sudo apt update
  sudo apt install -y ca-certificates curl gnupg

  sys_version=$(grep -w 'VERSION_CODENAME' /etc/os-release | awk -F '=' '{print $2}')

  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://${mirrors}/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  docker_list="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://${mirrors}/linux/debian ${sys_version} stable"
  sudo sh -c "echo $docker_list > /etc/apt/sources.list.d/docker.list"
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# centos
# https://docs.docker.com/engine/install/centos/
function centos_install(){
  (
    sudo sudo yum remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || exit 0
  )

  sudo yum install -y yum-utils
  sudo yum-config-manager --add-repo https://${mirrors}/linux/$1/docker-ce.repo
  (
    sudo yum makecache fast || sudo dnf makecache
  )
  sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# arch
# https://wiki.archlinux.org/title/Docker
function arch_install(){
  sudo pacman -S --noconfirm docker docker-compose
}

function set_registry_mirrors(){
   # 腾讯云内网镜像源
  ping -c 1 mirror.ccs.tencentyun.com &> /dev/null || return
  (
    sudo yum install -y jq || sudo apt install -y jq
  )
  jq '. + {"registry-mirrors": ["https://mirror.ccs.tencentyun.com"]}' /etc/docker/daemon.json > /tmp/docker-daemon.json \
  && sudo mv /tmp/docker-daemon.json /etc/docker/daemon.json
}

## 脚本开始 ##
mirrors="download.docker.com"
ping -c 1 google.com &> /dev/null || mirrors="mirrors.cloud.tencent.com/docker-ce"

# 版本选择
distro=$(grep '^ID=' /etc/os-release | awk -F '=' '{print $2}' | sed 's/"//g')
case  $distro in
  "debian")
    debian_install
    ;;
  "centos" | "almalinux")
    centos_install "centos"
    ;;
  "arch")
    arch_install
    ;;
  *)
    echo "退出！系统不支持"
    exit 1
    ;;
esac

# docker 配置
sudo mkdir -p /etc/docker
sudo curl -fsSL -o /etc/docker/daemon.json https://raw.githubusercontent.com/qvgz/sh/master/file/docker-daemon.json \
|| sudo curl -fsSL -o /etc/docker/daemon.json https://qvgz.org/sh/file/docker-daemon.json

set_registry_mirrors

# 非root 用户加入 docker 用户组
if [[ $(id -u) != "0" ]]; then
    sudo usermod -aG docker $USER
    newgrp docker
fi

sudo systemctl enable --now docker
