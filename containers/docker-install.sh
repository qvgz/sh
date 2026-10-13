#!/usr/bin/env bash
# 安装 Docker Engine
# 保留已有配置，追加可达的镜像加速源；首次安装写最小配置。

set -euo pipefail

if [[ ${1:-} == --help ]]; then
    printf '用法：sudo bash %s；DOCKER_MIRROR 指定仓库主机/路径（默认自动探测，Google 不可达时使用腾讯云）\n' "$0"
    exit 0
fi
(( $# == 0 )) || exit 2
[[ $EUID -eq 0 ]] || { printf '请以 root 执行\n' >&2; exit 1; }
[[ $(uname -s) == Linux && -f /etc/os-release ]] || exit 1
# shellcheck source=/dev/null
. /etc/os-release
# 可按需添加完整 URL（支持路径）或域名，按列表顺序探测。
registry_mirrors=(
    "https://mirror.ccs.tencentyun.com"
)
mirror=${DOCKER_MIRROR:-download.docker.com}
select_mirror() {
    if [[ -z ${DOCKER_MIRROR:-} ]]; then
        local status
        if status=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 \
            https://www.google.com/generate_204 2>/dev/null) && [[ $status == 204 ]]; then
            mirror=download.docker.com
        else
            mirror=mirrors.cloud.tencent.com/docker-ce
        fi
    fi
    printf 'Docker 安装源：%s\n' "$mirror"
}
[[ $mirror =~ ^[a-zA-Z0-9.-]+(/[a-zA-Z0-9._-]+)*$ ]] || { printf 'DOCKER_MIRROR 格式错误\n' >&2; exit 2; }
command -v systemctl >/dev/null || exit 1
case "$ID" in
    ubuntu|debian|centos|almalinux|rocky|arch) ;;
    *) printf '不支持系统：%s\n' "$ID" >&2; exit 1 ;;
esac
backup=$(mktemp -d /var/tmp/docker-install-backup.XXXXXX)
printf '配置备份：%s\n' "$backup"
for file in /etc/docker/daemon.json /etc/apt/keyrings/docker.gpg /etc/apt/sources.list.d/docker.list /etc/yum.repos.d/docker-ce.repo; do
    if [[ -e $file ]]; then cp -a --parents -- "$file" "$backup"; fi
done
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
case "$ID" in
    ubuntu|debian)
        codename=${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}
        [[ $codename =~ ^[a-zA-Z0-9._-]+$ ]] || { printf '缺少有效发行代号\n' >&2; exit 1; }
        apt-get update
        apt-get install -y ca-certificates curl gnupg jq iputils-ping
        select_mirror
        curl -fsS --connect-timeout 10 --max-time 60 "https://$mirror/linux/$ID/gpg" -o "$tmp/key"
        gpg --batch --yes --dearmor -o "$tmp/docker.gpg" "$tmp/key"
        install -D -m 0644 "$tmp/docker.gpg" /etc/apt/keyrings/docker.gpg
        printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://%s/linux/%s %s stable\n' \
            "$(dpkg --print-architecture)" "$mirror" "$ID" "$codename" >/etc/apt/sources.list.d/docker.list
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    centos|almalinux|rocky)
        yum install -y yum-utils curl ca-certificates jq iputils
        select_mirror
        curl -fsS --connect-timeout 10 --max-time 60 "https://$mirror/linux/centos/docker-ce.repo" -o "$tmp/docker-ce.repo"
        sed "s|download.docker.com|$mirror|g" "$tmp/docker-ce.repo" >/etc/yum.repos.d/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    arch) pacman -S --needed --noconfirm docker docker-compose jq iputils ;;
esac
if [[ ! -e /etc/docker/daemon.json && ! -L /etc/docker/daemon.json ]]; then
    printf '%s\n' '{"log-driver":"local","log-opts":{"max-size":"20m","max-file":"3"},"live-restore":true}' >"$tmp/daemon.json"
else
    cp -- /etc/docker/daemon.json "$tmp/daemon.json"
fi
for registry_mirror in "${registry_mirrors[@]}"; do
    [[ $registry_mirror == *://* ]] || registry_mirror="https://$registry_mirror"
    # ping 仅使用主机名，Docker 配置保留协议、端口和路径。
    host=${registry_mirror#*://}
    host=${host%%/*}
    host=${host%%:*}
    if ping -c 1 -W 1 -- "$host" >/dev/null 2>&1; then
        printf '添加镜像加速源：%s\n' "$registry_mirror"
        jq --arg mirror "$registry_mirror" \
            '.["registry-mirrors"] = (reduce ((.["registry-mirrors"] // []) + [$mirror])[] as $url
                ([]; if index($url) == null then . + [$url] else . end))' \
            "$tmp/daemon.json" >"$tmp/daemon.next.json"
        mv -- "$tmp/daemon.next.json" "$tmp/daemon.json"
    fi
done
dockerd --validate --config-file "$tmp/daemon.json"
if [[ ! -e /etc/docker/daemon.json && ! -L /etc/docker/daemon.json ]]; then
    install -D -m 0644 "$tmp/daemon.json" /etc/docker/daemon.json
elif ! cmp -s -- "$tmp/daemon.json" /etc/docker/daemon.json; then
    cat "$tmp/daemon.json" >/etc/docker/daemon.json
    printf '镜像加速配置已更新；已运行的 Docker 需择机重启生效。\n'
fi
systemctl enable --now docker
systemctl is-active --quiet docker
docker version
printf '安装完成；已有服务未主动重启，未修改用户组。软件包安装脚本可能重启服务。\n'
