#!/usr/bin/env bash
# 安装 Docker
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/docker.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/install/docker.sh)"

set -euo pipefail

DOCKER_MIRROR="download.docker.com"
TENCENT_MIRROR="mirrors.cloud.tencent.com/docker-ce"
DAEMON_JSON_PATH="/etc/docker/daemon.json"

log()   { echo -e "\033[32m[INFO]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1" >&2; exit 1; }

# sudo 兼容：root 下不需要 sudo
SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || error "非 root 执行但系统无 sudo"
  SUDO="sudo"
fi

# 环境探测
MIRROR="$DOCKER_MIRROR"
if ! curl -fsSL --connect-timeout 2 --max-time 4 "https://www.google.com" >/dev/null 2>&1; then
  log "切换至腾讯云镜像源"
  MIRROR="$TENCENT_MIRROR"
fi

# 获取发行版信息
distro="$(. /etc/os-release && echo "$ID")"
codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")"

install_docker() {
  case "$distro" in
    debian|ubuntu)
      $SUDO apt-get update
      $SUDO apt-get install -y ca-certificates curl gnupg jq

      $SUDO install -m 0755 -d /etc/apt/keyrings
      curl -fsSL "https://${MIRROR}/linux/${distro}/gpg" | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes

      # codename 不能为空，否则 repo 可能无效
      [[ -n "$codename" ]] || error "无法从 /etc/os-release 获取 VERSION_CODENAME/UBUNTU_CODENAME"

      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://${MIRROR}/linux/${distro} ${codename} stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

      $SUDO apt-get update
      $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    centos|almalinux|rocky)
      $SUDO yum install -y yum-utils jq curl

      $SUDO yum-config-manager --add-repo "https://${MIRROR}/linux/centos/docker-ce.repo"
      [[ -f /etc/yum.repos.d/docker-ce.repo ]] || error "docker-ce.repo 未生成，repo 添加失败"

      $SUDO sed -i "s|download.docker.com|${MIRROR}|g" /etc/yum.repos.d/docker-ce.repo
      $SUDO yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    arch)
      $SUDO pacman -S --noconfirm docker docker-compose jq
      ;;
    *)
      error "暂不支持的系统版本: $distro"
      ;;
  esac
}

configure_docker() {
  $SUDO mkdir -p /etc/docker

  # 破坏性写入前备份（若存在）
  if [[ -f "$DAEMON_JSON_PATH" ]]; then
    $SUDO cp -a "$DAEMON_JSON_PATH" "${DAEMON_JSON_PATH}.bak.$(date +%s)"
  fi

  # 基础配置（保持你原有配置项）
  cat <<'EOF' | $SUDO tee "$DAEMON_JSON_PATH" >/dev/null
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "local",
  "log-opts": { "max-size": "20m", "max-file": "3"},
  "storage-driver": "overlay2",
  "live-restore": true,
  "features": { "buildkit": true },
  "icc": false,
  "ip-masq": true,
  "ipv6": false,
  "max-concurrent-downloads": 5,
  "max-concurrent-uploads": 5,
  "shutdown-timeout": 10
}
EOF

  # 腾讯云内网加速：安全注入（registry-mirrors 默认空数组）
  if ping -c 1 -W 1 mirror.ccs.tencentyun.com &>/dev/null; then
    log "检测到腾讯云环境，注入内网镜像加速"
    tmp="$($SUDO mktemp)"
    $SUDO jq '.["registry-mirrors"] = ((.["registry-mirrors"] // []) + ["https://mirror.ccs.tencentyun.com"] | unique)' \
      "$DAEMON_JSON_PATH" > "$tmp"
    $SUDO mv "$tmp" "$DAEMON_JSON_PATH"
  fi

  # JSON 合法性校验（不改变功能，只防止写坏）
  $SUDO jq -e . "$DAEMON_JSON_PATH" >/dev/null || error "daemon.json 非法 JSON"

  # nofile nproc：systemd drop-in
  $SUDO mkdir -p /etc/systemd/system/docker.service.d
  cat <<'EOF' | $SUDO tee /etc/systemd/system/docker.service.d/10-nofile-nproc.conf >/dev/null
[Service]
LimitNOFILE=1048576
LimitNPROC=65535
TasksMax=infinity
EOF

  $SUDO systemctl daemon-reload
}

install_docker
configure_docker

# 用户组处理（仅在非 root 运行时）
if [[ "$(id -u)" -ne 0 ]]; then
  $SUDO usermod -aG docker "$USER"
  log "已将当前用户加入 docker 组，需重新登录或运行 'newgrp docker' 生效"
fi

$SUDO systemctl enable --now docker
log "Docker 安装完成！"
