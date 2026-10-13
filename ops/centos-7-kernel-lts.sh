#!/usr/bin/env bash
# CentOS 7 安装 kernel-lt
# 使用 grubby 选择默认内核，不自动重启。

set -euo pipefail
if [[ ${1:-} == --help ]]; then
    printf '用法：sudo bash %s；可用 ELREPO_RELEASE_URL 指定 EL7 release RPM\n' "$0"; exit 0
fi
(( $# == 0 )) || exit 2
[[ $EUID -eq 0 ]] || { printf '需要 root\n' >&2; exit 1; }
grep -q 'CentOS Linux 7' /etc/redhat-release 2>/dev/null || { printf '仅支持 CentOS 7\n' >&2; exit 1; }
for bin in yum rpm grubby sort; do
    command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; exit 1; }
done
backup=$(mktemp -d /var/tmp/kernel-lt-backup.XXXXXX)
grubby --default-kernel >"$backup/default-kernel"
for file in /etc/yum.repos.d/elrepo.repo /boot/grub2/grub.cfg /boot/grub2/grubenv /boot/efi/EFI/centos/grub.cfg /boot/efi/EFI/centos/grubenv; do
    [[ ! -e $file ]] || cp -a --parents -- "$file" "$backup"
done
printf '引导和仓库配置备份：%s\n' "$backup"
url=${ELREPO_RELEASE_URL:-https://mirrors.tuna.tsinghua.edu.cn/elrepo/elrepo/el7/x86_64/RPMS/elrepo-release-7.0-8.el7.elrepo.noarch.rpm}
[[ $url == https://* ]] || { printf 'release RPM 必须使用 HTTPS\n' >&2; exit 2; }
yum install -y "$url"
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-elrepo.org
yum -y --enablerepo=elrepo-kernel install kernel-lt kernel-lt-devel
version=$(rpm -q kernel-lt --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n 1)
kernel=/boot/vmlinuz-$version
[[ -f $kernel ]] || { printf '内核文件不存在：%s\n' "$kernel" >&2; exit 1; }
grubby --info "$kernel" >/dev/null
grubby --set-default "$kernel"
[[ $(grubby --default-kernel) == "$kernel" ]] || { printf '默认内核设置未生效\n' >&2; exit 1; }
printf '默认内核：%s；请在维护窗口手动重启。回退：grubby --set-default %s\n' "$kernel" "$(cat "$backup/default-kernel")"
