#!/usr/bin/env bash
# CentOS 9/10 容器云服务器优化
# 做什么：
# 1) 安装并启用 tuned（云虚拟机基线）
# 2) 安装启动时间同步 chrony
# 3) journald 限额（避免日志打爆系统盘）
# 4) 启动内核模块 br_netfilter nf_conntrack
# 5) sysctl
# 6) 配置 systemd 默认 nofile
# 7) 关闭：SELinux / firewalld
# 8) 配置 sshd
# 9) 配置时区 Asia/Shanghai
# 00) 验证
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/centos-optimize.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/centos-optimize.sh)"

set -euo pipefail

# -------------------------
# 只支持 CentOS 9/10
# -------------------------
codename=$(awk -F'.' '{print $1}' /etc/redhat-release | awk '{print $NF}')
case $codename in
  9|10)
    ;;
  *)
    echo "不支持该系统" >&2
    exit 1
esac

# -------------------------
# 0. 必须 root
# -------------------------
if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] 必须以 root 运行" >&2
  exit 1
fi

echo "== CentOS 9/10 Cloud Docker Enterprise Baseline =="

# -------------------------
# 1) 安装并启用 tuned（云虚拟机基线）
# -------------------------
dnf install -y tuned
systemctl enable --now tuned
tuned-adm profile virtual-guest

# -------------------------
# 2) 安装启动时间同步 chrony
# -------------------------
dnf install -y chrony
systemctl enable --now chronyd

# -------------------------
# 3) journald 限额（避免日志打爆系统盘）
# -------------------------
# 避免 /var/log 或 journal 无限增长导致根分区满
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/10-enterprise-cloud.conf <<'EOF'
[Journal]
# 最大占用
SystemMaxUse=2G
# 运行时 journal（/run/log/journal）上限
RuntimeMaxUse=512M
EOF
systemctl restart systemd-journald

# -------------------------
# 4) 启动内核模块 br_netfilter nf_conntrack
# -------------------------
# br_netfilter：bridge 流量进入 netfilter（iptables/nft 才能管得到）
# nf_conntrack：连接跟踪（Docker NAT/端口映射依赖）
cat > /etc/modules-load.d/docker-cloud.conf <<'EOF'
br_netfilter
nf_conntrack
EOF
modprobe br_netfilter || true
modprobe nf_conntrack || true

# -------------------------
# 5) sysctl
# -------------------------
# 文件：/etc/sysctl.d/99-cloud-docker.conf
cat > /etc/sysctl.d/99-cloud-docker.conf <<'EOF'
################################################################
# Cloud + Docker Enterprise sysctl baseline (CentOS 9/10)
# 原则：稳妥优先；不默认启用策略性强/争议项（如 BBR、激进 vm.*）
################################################################

############################
# A) 网络并发与队列（低风险提升稳定性）
############################
net.core.somaxconn = 32768            # 优点：listen backlog 更大，突发并发更稳；代价：少量内核内存
net.core.netdev_max_backlog = 32768   # 优点：网卡收包队列更大，突发不易丢包；代价：少量内核内存
net.ipv4.tcp_max_syn_backlog = 16384  # 优点：半连接队列更大，SYN 洪峰更稳；代价：少量内核内存

############################
# B) TCP 缓冲（适度放宽，不激进）
############################
net.ipv4.tcp_window_scaling = 1       # 优点：支持大窗口吞吐；代价：无明显
net.core.rmem_default = 262144        # 优点：默认收缓冲更大；代价：高并发时内存略增
net.core.wmem_default = 262144        # 优点：默认发缓冲更大；代价：高并发时内存略增
net.core.rmem_max = 16777216          # 优点：允许更高吞吐；代价：仅“允许上限”，本身不占用
net.core.wmem_max = 16777216          # 优点：允许更高吞吐；代价：仅“允许上限”，本身不占用
net.ipv4.tcp_rmem = 4096 87380 16777216  # 优点：TCP 收缓冲范围；代价：高并发时内存可上升
net.ipv4.tcp_wmem = 4096 65536 16777216  # 优点：TCP 发缓冲范围；代价：高并发时内存可上升

############################
# C) TCP 稳定性（线上常用、低风险）
############################
net.ipv4.tcp_syncookies = 1           # 优点：缓解 SYN flood；代价：极小
net.ipv4.tcp_mtu_probing = 1          # 优点：缓解 PMTU 黑洞（部分云网络）；代价：极小
net.ipv4.tcp_tw_reuse = 1             # 优点：短连接主动发起方更稳；代价：收益因业务而异（非万能项）

############################
# D) Docker/容器网络必需项
############################
net.ipv4.ip_forward = 1               # 优点：容器转发/NAT 必需；代价：无明显
net.bridge.bridge-nf-call-iptables = 1  # 优点：bridge 流量纳入 netfilter，策略可控；代价：轻微 CPU 开销
net.bridge.bridge-nf-call-ip6tables = 1 # 优点：同上（IPv6）；代价：轻微 CPU 开销

############################
# E) 连接跟踪（Docker NAT/端口映射依赖）
############################
net.netfilter.nf_conntrack_max = 262144  # 优点：高连接数更稳；代价：占用内存（连接越多越占）

############################
# F) 文件描述符：系统总量与单进程硬上限（容器/高并发服务建议）
############################
fs.file-max = 2097152                 # 优点：全系统 FD 总池子更大；代价：仅“允许上限”，本身不占用
fs.nr_open = 2097152                  # 优点：单进程 ulimit 上限更高（runc/setrlimit 不易失败）；代价：极小

############################
# G) 低风险网络 hardening（企业常见基线）
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

# 应用 sysctl（用 --system 会加载 /etc/sysctl.d/*.conf）
sysctl --system >/dev/null

# -------------------------
# 6) 配置 systemd 默认 nofile
# -------------------------
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/10-nofile.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
EOF
systemctl daemon-reexec

# -------------------------
# 7) 关闭：SELinux / firewalld
# -------------------------
# SELinux
setenforce 0 || true
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
# firewalld
systemctl disable --now firewalld || true

# -------------------------
# 8) 配置 sshd
# -------------------------
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/90-enterprise.conf <<'EOF'
KbdInteractiveAuthentication no
GSSAPIAuthentication no
UseDNS no
EOF
sshd -t && systemctl reload sshd || true

# -------------------------
# 9) 配置时区 Asia/Shanghai
# -------------------------
timedatectl set-timezone Asia/Shanghai || true

# -------------------------
# 00) 验证
# -------------------------
echo "== 验证 =="
echo -e "\n-- tuned --"
systemctl is-active tuned >/dev/null 2>&1 && echo "tuned: active" || echo "tuned: not active"
tuned-adm active || true

echo -e "\n-- chrony --"
systemctl is-active chronyd >/dev/null 2>&1 && echo "chronyd: active" || echo "chronyd: not active"
chronyc sources -n | awk '$1=="^*" {print}' || true

echo -e "\n-- sysctl --"
sysctl net.netfilter.nf_conntrack_max \
       net.ipv4.ip_forward \
       net.bridge.bridge-nf-call-iptables \
       || true

echo -e "\n-- systemd 默认 nofile --"
systemctl show -p DefaultLimitNOFILE

echo -e "\n-- sshd --"
sshd -T | grep -E 'usedns|gssapiauthentication|kbdinteractiveauthentication' || true

echo -e "\n-- 时区 --"
date
