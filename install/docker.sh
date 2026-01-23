#!/bin/bash
# 安装 Docker
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/docker.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/install/docker.sh)"

set -euo pipefail

# --- 配置参数 ---
DOCKER_MIRROR="download.docker.com"
TENCENT_MIRROR="mirrors.cloud.tencent.com/docker-ce"
DAEMON_JSON_PATH="/etc/docker/daemon.json"

# --- 辅助函数 ---
log() { echo -e "\033[32m[INFO]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

# 环境探测
if ! ping -c 1 -W 2 google.com &> /dev/null; then
    log "国内网络环境切换至腾讯云镜像源"
    MIRROR=$TENCENT_MIRROR
else
    MIRROR=$DOCKER_MIRROR
fi

# 获取发行版信息
distro=$(grep '^ID=' /etc/os-release | awk -F '=' '{print $2}' | sed 's/"//g')
codename=$(grep 'VERSION_CODENAME' /etc/os-release | awk -F '=' '{print $2}' | sed 's/"//g')

# --- 安装函数 ---
install_docker() {
    case $distro in
        "debian" | "ubuntu")
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg jq
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://${MIRROR}/linux/${distro}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://${MIRROR}/linux/${distro} ${codename:-stable} stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        "centos" | "almalinux" | "rocky")
            sudo yum install -y yum-utils jq
            sudo yum-config-manager --add-repo https://${MIRROR}/linux/centos/docker-ce.repo
            sudo sed -i "s|download.docker.com|${MIRROR}|g" /etc/yum.repos.d/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        "arch")
            sudo pacman -S --noconfirm docker docker-compose jq
            ;;
        *)
            error "暂不支持的系统版本: $distro"
            ;;
    esac
}

# --- 配置 Docker ---
configure_docker() {
    sudo mkdir -p /etc/docker
    # 基础配置
    cat <<EOF | sudo tee $DAEMON_JSON_PATH > /dev/null
{
    "exec-opts": [
        "native.cgroupdriver=systemd"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "20m",
        "max-file": "3",
        "compress": "true"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "features": {
        "buildkit": true
    },
    "icc": false,
    "ip-masq": true,
    "ipv6": false,
    "max-concurrent-downloads": 5,
    "max-concurrent-uploads": 5,
    "shutdown-timeout": 10
}
EOF

    # 动态注入腾讯云内网加速（如果是腾讯云环境）
    if ping -c 1 -W 1 mirror.ccs.tencentyun.com &> /dev/null; then
        log "检测到腾讯云环境，注入内网镜像加速"
        tmp=$(mktemp)
        jq '.["registry-mirrors"] += ["https://mirror.ccs.tencentyun.com"]' $DAEMON_JSON_PATH > "$tmp" && sudo mv "$tmp" $DAEMON_JSON_PATH
    fi
}

# --- 主流程 ---
install_docker
configure_docker

# 用户组处理
if [[ $(id -u) != "0" ]]; then
    sudo usermod -aG docker "$USER"
    log "已将当前用户加入 docker 组，需重新登录或运行 'newgrp docker' 生效"
fi

sudo systemctl enable --now docker
log "Docker 安装完成！"
