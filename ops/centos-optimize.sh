#!/usr/bin/env bash
# CentOS/Alma/Rocky 9/10 容器云服务器优化
# 包含：
# - 基础组件：安装并启用 tuned、chrony
# - 日志与内核：journald 持久化与限额、容器内核模块、sysctl（含关闭 IPv6）
# - 系统访问基线：关闭 SELinux / firewalld、配置 sshd
# - 可选项：
#  --global-limits 配置全局 nofile nproc
#  --timezone-shanghai 配置时区 Asia/Shanghai
# - 验证：检查关键配置是否生效
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/centos-optimize.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/centos-optimize.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/centos-optimize.sh)" --timezone-shanghai --global-limits

set -euo pipefail

ENABLE_TIMEZONE_SHANGHAI=0
ENABLE_GLOBAL_LIMITS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timezone-shanghai)
      ENABLE_TIMEZONE_SHANGHAI=1
      ;;
    --global-limits)
      ENABLE_GLOBAL_LIMITS=1
      ;;
    -h|--help)
      echo "用法: $0 [--timezone-shanghai] [--global-limits]"
      exit 0
      ;;
    *)
      echo "[ERROR] 不支持的参数: $1" >&2
      echo "用法: $0 [--timezone-shanghai] [--global-limits]" >&2
      exit 1
      ;;
  esac
  shift
done

# -------------------------
# 环境检查：只支持 CentOS/Alma/Rocky 9/10
# -------------------------
# shellcheck disable=SC1091
. /etc/os-release
distro_id="${ID:-}"
distro_name="${NAME:-}"
distro_major="$(echo "${VERSION_ID:-}" | awk -F'.' '{print $1}')"
case "$distro_id:$distro_major" in
  centos:9|centos:10|almalinux:9|almalinux:10|rocky:9|rocky:10)
    ;;
  *)
    echo "不支持该系统：${distro_name:-unknown} ${distro_major:-unknown}" >&2
    exit 1
    ;;
esac

# -------------------------
# 环境检查：必须 root
# -------------------------
if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] 必须以 root 运行" >&2
  exit 1
fi

echo "== CentOS/Alma/Rocky 9/10 Container Cloud Baseline =="

# -------------------------
# 基础组件：tuned（云虚拟机基线）
# -------------------------
dnf install -y tuned
systemctl enable --now tuned
tuned-adm profile virtual-guest

# -------------------------
# 基础组件：chrony 时间同步
# -------------------------
dnf install -y chrony
systemctl enable --now chronyd

# -------------------------
# 日志与内核：journald 持久化与限额
# -------------------------
# 云主机保留重启前日志更利于排障，同时限制占用避免打满系统盘。
mkdir -p /etc/systemd/journald.conf.d
mkdir -p /var/log/journal
cat > /etc/systemd/journald.conf.d/10-el-container-cloud.conf <<'EOF'
[Journal]
# 容器云主机默认保留持久日志，便于重启后排障。
Storage=persistent
# 控制磁盘占用，避免日志无限增长挤压系统盘。
SystemMaxUse=1G
# 运行时 journal（/run/log/journal）上限
RuntimeMaxUse=256M
EOF
systemctl restart systemd-journald

# -------------------------
# 日志与内核：容器内核模块
# -------------------------
# br_netfilter：bridge 流量进入 netfilter（iptables/nft 才能管得到）
# nf_conntrack：连接跟踪（Docker NAT/端口映射依赖）
# overlay：容器镜像/容器层常用联合挂载驱动
cat > /etc/modules-load.d/10-el-container-cloud.conf <<'EOF'
overlay
br_netfilter
nf_conntrack
EOF
modprobe overlay || true
modprobe br_netfilter || true
modprobe nf_conntrack || true

# -------------------------
# 日志与内核：sysctl
# -------------------------
# 文件：/etc/sysctl.d/99-el-container-cloud.conf
cat > /etc/sysctl.d/99-el-container-cloud.conf <<'EOF'
################################################################
# EL 9/10 container cloud sysctl baseline
# 原则：仅保留容器主机必需项、低风险通用项，避免固定高内存/高连接数参数。
################################################################

############################
# A) 网络并发（适度提高上限，兼顾默认应用场景）
############################
net.core.somaxconn = 16384            # 避免高并发 listen backlog 过小；保留适度上限，避免过度放大
net.ipv4.tcp_max_syn_backlog = 16384  # 降低突发建连时半连接队列不足的概率

############################
# B) TCP 稳定性与端口资源
############################
net.ipv4.ip_local_port_range = 10240 65535  # 提高出站短连接可用端口数，减少端口耗尽概率
net.ipv4.tcp_syncookies = 1                # 缓解 SYN flood
net.ipv4.tcp_mtu_probing = 1               # 缓解部分云网络 PMTU 黑洞

############################
# C) 容器网络必需项
############################
net.ipv4.ip_forward = 1                    # Docker/Podman bridge NAT 依赖
net.bridge.bridge-nf-call-iptables = 1    # 让 bridge 流量进入 netfilter

############################
# D) IPv6
############################
# 本脚本按 IPv4-only 容器云主机基线处理，默认关闭 IPv6。
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

############################
# E) 低风险网络 hardening
############################
net.ipv4.conf.all.accept_redirects = 0     # 优点：降低被重定向风险；代价：极小
net.ipv4.conf.default.accept_redirects = 0 # 优点：同上；代价：极小
net.ipv4.conf.all.send_redirects = 0       # 优点：避免充当路由重定向源；代价：极小
net.ipv4.conf.default.send_redirects = 0   # 优点：同上；代价：极小
net.ipv4.conf.all.accept_source_route = 0  # 优点：禁用源路由，减少攻击面；代价：极小
net.ipv4.conf.default.accept_source_route = 0 # 优点：同上；代价：极小
net.ipv4.icmp_ignore_bogus_error_responses = 1 # 优点：忽略异常 ICMP 错误响应；代价：极小

# rp_filter：Docker/多网卡/overlay 环境建议用 loose(2)，避免误杀回程路径
net.ipv4.conf.all.rp_filter = 2            # 优点：减少欺骗；代价：不如 strict(1) 严格，但更兼容容器网络
net.ipv4.conf.default.rp_filter = 2        # 优点：同上；代价：同上
EOF

# 仅加载本脚本写入的配置，避免受其他 sysctl 文件影响。
sysctl -q --load /etc/sysctl.d/99-el-container-cloud.conf

# -------------------------
# 可选项：配置全局 nofile nproc
# -------------------------
conf_global_nofile_nproc(){
  # 将系统级 FD 上限与本脚本的全局 limits 选项绑定，避免默认改动进程资源上限。
  cat > /etc/sysctl.d/10-el-global-limits.conf <<'EOF'
fs.file-max = 2097152
fs.nr_open = 2097152
EOF
  sysctl -q --load /etc/sysctl.d/10-el-global-limits.conf

  # systemd nofile nproc
  mkdir -p /etc/systemd/system.conf.d
  cat > /etc/systemd/system.conf.d/10-el-global-limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65535
TasksMax=infinity
EOF
  systemctl daemon-reexec

  # 终端进程 nofile nproc
  mkdir -p /etc/security/limits.d/
  cat > /etc/security/limits.d/10-el-global-limits.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
EOF
}

if [[ "$ENABLE_GLOBAL_LIMITS" -eq 1 ]]; then
  conf_global_nofile_nproc
fi

# -------------------------
# 系统访问基线：关闭 SELinux / firewalld
# -------------------------
# SELinux
setenforce 0 || true
# 统一覆盖 SELINUX 当前状态，避免 permissive 时未持久关闭。
if [[ -f /etc/selinux/config ]]; then
  if grep -qE '^[[:space:]]*SELINUX=' /etc/selinux/config; then
    sed -ri 's/^[[:space:]]*SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
  else
    printf '\nSELINUX=disabled\n' >> /etc/selinux/config
  fi
fi
# firewalld
systemctl disable --now firewalld || true

# -------------------------
# 系统访问基线：sshd
# -------------------------
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/90-enterprise.conf <<'EOF'
KbdInteractiveAuthentication no
GSSAPIAuthentication no
UseDNS no
EOF
sshd -t && systemctl reload sshd || true

# -------------------------
# 可选项：时区 Asia/Shanghai
# -------------------------
if [[ "$ENABLE_TIMEZONE_SHANGHAI" -eq 1 ]]; then
  timedatectl set-timezone Asia/Shanghai || true
fi

# -------------------------
# 验证
# -------------------------
echo "== 验证 =="
echo -e "\n-- tuned --"
systemctl is-active tuned >/dev/null 2>&1 && echo "tuned: active" || echo "tuned: not active"
tuned-adm active || true

echo -e "\n-- chrony --"
systemctl is-active chronyd >/dev/null 2>&1 && echo "chronyd: active" || echo "chronyd: not active"
chronyc sources -n | awk '$1=="^*" {print}' || true

echo -e "\n-- journald --"
journalctl --disk-usage || true

echo -e "\n-- sysctl --"
sysctl net.core.somaxconn \
       net.ipv4.tcp_max_syn_backlog \
       net.ipv4.ip_local_port_range \
       net.ipv4.ip_forward \
       net.bridge.bridge-nf-call-iptables \
       net.ipv6.conf.all.disable_ipv6 \
       net.ipv4.conf.all.rp_filter \
       || true

echo -e "\n-- systemd 默认 nofile --"
if [[ "$ENABLE_GLOBAL_LIMITS" -eq 1 ]]; then
  systemctl show -p DefaultLimitNOFILE -p DefaultLimitNPROC -p DefaultTasksMax
  sysctl fs.file-max fs.nr_open || true
else
  echo "skip: 未启用 --global-limits"
fi

echo -e "\n-- sshd --"
sshd -T | grep -E 'usedns|gssapiauthentication|kbdinteractiveauthentication' || true

echo -e "\n-- 时区 --"
if [[ "$ENABLE_TIMEZONE_SHANGHAI" -eq 1 ]]; then
  timedatectl show -p Timezone --value || true
fi
date
