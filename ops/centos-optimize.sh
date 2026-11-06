#!/usr/bin/env bash
# EL 9/10 容器主机基线
# 共有：tuned、chrony、journald、limits、SELinux permissive、关闭 firewalld、sshd、关闭 swap、时区、公共 sysctl；按场景 docker|k8s 追加内核配置。可重复执行。

set -euo pipefail

TAG=el-container-cloud
MODE=""
BACKUP="" CHANGED=0

usage() { printf '用法: %s docker|k8s\n  docker  Docker 云主机\n  k8s     云主机 K8s 节点\n' "$0"; }
log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# backup_file 路径：首次改动前备份原文件，不存在则记入 created.list
backup_file() {
    if [[ -e $1 ]]; then
        [[ -e $BACKUP$1 ]] || cp -a --parents -- "$1" "$BACKUP"
    elif ! grep -qxF -- "$1" "$BACKUP/created.list" 2>/dev/null; then
        printf '%s\n' "$1" >>"$BACKUP/created.list"
    fi
}

# put_file 路径 < 内容：内容不同才写入，CHANGED=1 表示已改动
put_file() {
    local path=$1 content
    content=$(cat)
    CHANGED=0
    if [[ -f $path && $(<"$path") == "$content" ]]; then
        log "无变化 $path"
        return 0
    fi
    backup_file "$path"
    mkdir -p -- "$(dirname -- "$path")"
    printf '%s\n' "$content" >"$path"
    CHANGED=1
    log "已写入 $path"
}

# kernel_conf 名称 模块... < sysctl 内容：持久化并立即加载；模块先于 sysctl
kernel_conf() {
    local name=$1
    shift
    put_file "/etc/modules-load.d/10-el-$name.conf" < <(printf '%s\n' "$@")
    modprobe -a "$@"
    put_file "/etc/sysctl.d/99-el-$name.conf"
    sysctl -q --load "/etc/sysctl.d/99-el-$name.conf"
}

# kernel_conf_remove 名称：切换场景时移除另一场景的配置，运行时值重启后恢复
kernel_conf_remove() {
    local f
    for f in "/etc/modules-load.d/10-el-$1.conf" "/etc/sysctl.d/99-el-$1.conf"; do
        [[ -e $f ]] || continue
        backup_file "$f"
        rm -f -- "$f"
        log "已移除 $f"
    done
}

parse_args() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
        docker|k8s) (($# == 1)) || { usage >&2; die "参数过多"; }; MODE=$1 ;;
        *) usage >&2; die "需指定场景 docker 或 k8s" ;;
    esac
}

preflight() {
    local bin
    ((EUID == 0)) || die "必须以 root 运行"
    [[ -r /etc/os-release ]] || die "缺少 /etc/os-release"
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID:-}:${VERSION_ID%%.*}" in
        centos:9|centos:10|almalinux:9|almalinux:10|rocky:9|rocky:10) ;;
        *) die "不支持该系统: ${PRETTY_NAME:-unknown}" ;;
    esac
    for bin in dnf systemctl modprobe sysctl sshd timedatectl swapon swapoff getenforce setenforce; do
        command -v "$bin" >/dev/null || die "缺少命令: $bin"
    done
    [[ $(stat -fc %T /sys/fs/cgroup) == cgroup2fs ]] || warn "未使用 cgroup v2，Docker 与 K8s 推荐 cgroup v2"
    sshd -t || die "现有 sshd 配置校验失败"
}

snapshot() {
    BACKUP=$(mktemp -d "/var/tmp/$TAG-backup.XXXXXX")
    sysctl -a >"$BACKUP/sysctl.before" 2>/dev/null || true
    swapon --show >"$BACKUP/swap.before" 2>&1 || true
    getenforce >"$BACKUP/selinux.before" 2>&1 || true
    systemctl is-enabled firewalld >"$BACKUP/firewalld.enabled" 2>&1 || true
    systemctl is-active firewalld >"$BACKUP/firewalld.active" 2>&1 || true
    tuned-adm active >"$BACKUP/tuned.before" 2>&1 || true
    timedatectl show -p Timezone --value >"$BACKUP/timezone.before" || true
    log "备份目录: $BACKUP（created.list 为新增文件）"
}

# ==================== 共有 ====================

setup_services() {
    local profile
    dnf install -y -q tuned chrony
    systemctl enable --now tuned chronyd
    profile=$(tuned-adm recommend)
    [[ -n $profile ]] || die "tuned-adm recommend 无输出"
    tuned-adm profile "$profile"
    log "tuned profile: $profile"
}

setup_journald() {
    mkdir -p /var/log/journal
    put_file /etc/systemd/journald.conf.d/10-$TAG.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=1G
RuntimeMaxUse=256M
EOF
    if ((CHANGED)); then systemctl restart systemd-journald; fi
}

# 不设 fs.file-max/nr_open：内核与 systemd 默认已远大于 1048576
setup_limits() {
    put_file /etc/systemd/system.conf.d/10-$TAG.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
EOF
    if ((CHANGED)); then systemctl daemon-reexec; fi

    put_file /etc/security/limits.d/10-$TAG.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
EOF
}

setup_selinux() {
    local conf=/etc/selinux/config
    if [[ $(getenforce) == Enforcing ]]; then setenforce 0; fi
    [[ -f $conf ]] || return 0
    if grep -qE '^[[:space:]]*SELINUX=disabled' "$conf"; then
        warn "原配置为 disabled，改为 permissive 后下次启动建议 touch /.autorelabel 重新打标签"
    fi
    if grep -qE '^[[:space:]]*SELINUX=' "$conf"; then
        put_file "$conf" < <(sed -r 's/^[[:space:]]*SELINUX=.*/SELINUX=permissive/' "$conf")
    else
        put_file "$conf" < <(cat "$conf"; printf 'SELINUX=permissive\n')
    fi
}

setup_firewalld() {
    if systemctl cat firewalld.service >/dev/null 2>&1; then
        systemctl disable --now firewalld
    else
        log "未安装 firewalld，跳过"
    fi
}

# sshd 取首次出现的值，须排在发行版 50-redhat.conf 之前
setup_sshd() {
    local expect got
    put_file /etc/ssh/sshd_config.d/10-$TAG.conf <<'EOF'
KbdInteractiveAuthentication no
GSSAPIAuthentication no
UseDNS no
EOF
    sshd -t
    expect=$'gssapiauthentication no\nkbdinteractiveauthentication no\nusedns no'
    got=$(sshd -T | grep -E '^(gssapiauthentication|kbdinteractiveauthentication|usedns) ' | sort)
    [[ $got == "$expect" ]] || die "sshd 配置未生效（检查 Include sshd_config.d 或更早的同名配置）: $got"
    if ((CHANGED)); then systemctl reload sshd; fi
}

setup_swap() {
    if [[ -f /etc/fstab ]]; then
        put_file /etc/fstab < <(awk '!/^[[:space:]]*#/ && $3 == "swap" {$0 = "#" $0} 1' /etc/fstab)
        if ((CHANGED)); then systemctl daemon-reload; fi
    fi
    swapoff -a
    [[ -z $(swapon --show --noheadings) ]] || die "swap 仍启用: $(swapon --show --noheadings)"
}

setup_timezone() {
    [[ $(timedatectl show -p Timezone --value) == Asia/Shanghai ]] || timedatectl set-timezone Asia/Shanghai
}

# ip_forward 须在 conf.* 之前：修改 ip_forward 会重置部分 IPv4 conf 参数；场景文件按文件名排在其后加载
setup_common_kernel() {
    kernel_conf container-cloud overlay <<'EOF'
net.ipv4.ip_forward = 1

# inotify 实例默认 128；EL9 max_map_count 默认 65530
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 1048576
vm.max_map_count = 1048576

# 高并发：连接队列、出站端口、邻居表
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 32768 65535
net.ipv4.neigh.default.gc_thresh1 = 8192
net.ipv4.neigh.default.gc_thresh2 = 32768
net.ipv4.neigh.default.gc_thresh3 = 65536
net.ipv6.neigh.default.gc_thresh1 = 8192
net.ipv6.neigh.default.gc_thresh2 = 32768
net.ipv6.neigh.default.gc_thresh3 = 65536
EOF
}

# ==================== Docker 云主机 ====================

setup_docker() {
    kernel_conf_remove k8s
    kernel_conf docker nf_conntrack <<'EOF'
# 不收发 ICMP 重定向；rp_filter 宽松模式兼容多网卡、非对称路由
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2

# 容器 NAT 连接跟踪
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_buckets = 262144
EOF
}

# ==================== 云主机 K8s 节点 ====================

# rp_filter、conntrack 由 CNI 与 kube-proxy 管理
setup_k8s() {
    kernel_conf_remove docker
    kernel_conf k8s br_netfilter <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
}

report() {
    echo "== 核验 =="
    printf '场景: %s\n' "$MODE"
    printf 'tuned: %s，%s\n' "$(systemctl is-active tuned || true)" "$(tuned-adm active 2>&1 || true)"
    printf 'chronyd: %s，同步源: %s\n' "$(systemctl is-active chronyd || true)" \
        "$(chronyc -n sources 2>/dev/null | awk '$1 == "^*" {print $2}' || true)"
    journalctl --disk-usage || true
    systemctl show -p DefaultLimitNOFILE || true
    printf 'SELinux: %s，firewalld: %s，swap: %s 个\n' "$(getenforce || true)" \
        "$(systemctl is-active firewalld 2>/dev/null || true)" "$(swapon --show --noheadings | wc -l)"
    printf '时区: %s\n' "$(timedatectl show -p Timezone --value || true)"
    sysctl net.ipv4.ip_forward fs.inotify.max_user_instances vm.max_map_count net.core.somaxconn 2>&1 || true
    case $MODE in
        docker) sysctl net.ipv4.conf.all.rp_filter net.netfilter.nf_conntrack_max 2>&1 || true ;;
        k8s) sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables 2>&1 || true ;;
    esac
}

main() {
    parse_args "$@"
    preflight
    snapshot
    setup_services
    setup_journald
    setup_limits
    setup_selinux
    setup_firewalld
    setup_sshd
    setup_swap
    setup_timezone
    setup_common_kernel
    case $MODE in
        docker) setup_docker ;;
        k8s) setup_k8s ;;
    esac
    report
}

main "$@"
