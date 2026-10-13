#!/usr/bin/env bash
# EL 9/10 容器主机基线
# 安全策略关闭需显式选项。

set -euo pipefail

ENABLE_TIMEZONE_SHANGHAI=0
ENABLE_GLOBAL_LIMITS=0
DISABLE_SELINUX=0
DISABLE_FIREWALLD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timezone-shanghai)
      ENABLE_TIMEZONE_SHANGHAI=1
      ;;
    --disable-selinux) DISABLE_SELINUX=1 ;;
    --disable-firewalld) DISABLE_FIREWALLD=1 ;;
    --global-limits)
      ENABLE_GLOBAL_LIMITS=1
      ;;
    -h|--help)
      echo "用法: $0 [--timezone-shanghai] [--global-limits] [--disable-selinux] [--disable-firewalld]"
      exit 0
      ;;
    *)
      echo "[ERROR] 不支持的参数: $1" >&2
      echo "用法: $0 [--timezone-shanghai] [--global-limits] [--disable-selinux] [--disable-firewalld]" >&2
      exit 1
      ;;
  esac
  shift
done

# shellcheck disable=SC1091
. /etc/os-release
distro_id="${ID:-}"
distro_name="${NAME:-}"
distro_major=${VERSION_ID%%.*}
case "$distro_id:$distro_major" in
  centos:9|centos:10|almalinux:9|almalinux:10|rocky:9|rocky:10)
    ;;
  *)
    echo "不支持该系统：${distro_name:-unknown} ${distro_major:-unknown}" >&2
    exit 1
    ;;
esac

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] 必须以 root 运行" >&2
  exit 1
fi

for bin in dnf systemctl modprobe sysctl sshd; do
  command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; exit 1; }
done
if (( DISABLE_SELINUX )); then
  command -v getenforce >/dev/null && command -v setenforce >/dev/null
fi
sshd -t
backup=$(mktemp -d /var/tmp/el-container-backup.XXXXXX)
for file in /etc/systemd/journald.conf.d/10-el-container-cloud.conf /etc/modules-load.d/10-el-container-cloud.conf /etc/sysctl.d/99-el-container-cloud.conf /etc/sysctl.d/10-el-global-limits.conf /etc/systemd/system.conf.d/10-el-global-limits.conf /etc/security/limits.d/10-el-global-limits.conf /etc/selinux/config /etc/ssh/sshd_config.d/90-enterprise.conf; do
  [[ ! -e $file ]] || cp -a --parents -- "$file" "$backup"
done
sysctl -a 2>/dev/null >"$backup/sysctl.before" || true
systemctl is-enabled firewalld >"$backup/firewalld.enabled" 2>/dev/null || true
systemctl is-active firewalld >"$backup/firewalld.active" 2>/dev/null || true
tuned-adm active >"$backup/tuned.before" 2>/dev/null || true
timedatectl show -p Timezone --value >"$backup/timezone.before"
printf '原配置和状态备份：%s\n' "$backup"

dnf install -y tuned chrony
systemctl enable --now tuned
tuned-adm profile virtual-guest

systemctl enable --now chronyd

mkdir -p /etc/systemd/journald.conf.d
mkdir -p /var/log/journal
cat > /etc/systemd/journald.conf.d/10-el-container-cloud.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=1G
RuntimeMaxUse=256M
EOF
systemctl restart systemd-journald

cat > /etc/modules-load.d/10-el-container-cloud.conf <<'EOF'
overlay
br_netfilter
nf_conntrack
EOF
modprobe overlay
modprobe br_netfilter
modprobe nf_conntrack

cat > /etc/sysctl.d/99-el-container-cloud.conf <<'EOF'
net.ipv4.tcp_syncookies = 1

net.ipv4.ip_forward = 1

net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

net.ipv4.icmp_echo_ignore_broadcasts = 1

net.ipv4.icmp_ignore_bogus_error_responses = 1

net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2

net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
EOF

sysctl -q --load /etc/sysctl.d/99-el-container-cloud.conf

conf_global_nofile_nproc(){
  cat > /etc/sysctl.d/10-el-global-limits.conf <<'EOF'
fs.file-max = 2097152
fs.nr_open = 2097152
EOF
  sysctl -q --load /etc/sysctl.d/10-el-global-limits.conf

  mkdir -p /etc/systemd/system.conf.d
  cat > /etc/systemd/system.conf.d/10-el-global-limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65535
DefaultTasksMax=infinity
EOF
  systemctl daemon-reexec

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

if (( DISABLE_SELINUX )); then
if [[ $(getenforce) != Disabled ]]; then setenforce 0; fi
if [[ -f /etc/selinux/config ]]; then
  if grep -qE '^[[:space:]]*SELINUX=' /etc/selinux/config; then
    sed -ri 's/^[[:space:]]*SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
  else
    printf '\nSELINUX=disabled\n' >> /etc/selinux/config
  fi
fi
fi
if (( DISABLE_FIREWALLD )); then systemctl disable --now firewalld; fi

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/90-enterprise.conf <<'EOF'
KbdInteractiveAuthentication no
GSSAPIAuthentication no
UseDNS no
EOF
sshd -t
systemctl reload sshd

if [[ "$ENABLE_TIMEZONE_SHANGHAI" -eq 1 ]]; then
  timedatectl set-timezone Asia/Shanghai
fi

echo "== 验证 =="
echo -e "\n-- tuned --"
systemctl is-active tuned >/dev/null 2>&1 && echo "tuned: active" || echo "tuned: not active"
tuned-adm active || true

echo -e "\n-- chrony --"
systemctl is-active chronyd >/dev/null 2>&1 && echo "chronyd: active" || echo "chronyd: not active"
chronyc sources -n | awk '$1=="^*" {print}' || true

echo -e "\n-- journald --"
journalctl --disk-usage || true

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
