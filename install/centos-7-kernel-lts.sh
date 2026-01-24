#!/usr/bin/env bash
# 安装 CentOS 7 ELRepo LTS 内核（kernel-lt）
# 自动适配 BIOS 和 UEFI 引导模式
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/centos-7-kernel-lts.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/install/centos-7-kernel-lts.sh)"

set -euo pipefail

# 1) 权限与系统检查
if [[ ${EUID} -ne 0 ]]; then
  echo "Error: 本脚本需要 Root 权限执行。" >&2
  exit 1
fi

if ! grep -q "CentOS Linux 7" /etc/redhat-release 2>/dev/null; then
  echo "Error: 本脚本仅支持 CentOS 7 系统。" >&2
  exit 1
fi

# 2) 依赖检查（最小集合）
for bin in yum rpm sed cp grub2-mkconfig grub2-set-default grub2-editenv awk grep; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: 缺少命令: $bin" >&2; exit 1; }
done

echo "==> 正在安装 ELRepo Release 包..."
# 不吞错：失败直接退出，避免后续步骤误跑
yum install -y https://mirrors.tuna.tsinghua.edu.cn/elrepo/elrepo/el7/x86_64/RPMS/elrepo-release-7.0-8.el7.elrepo.noarch.rpm
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-elrepo.org

echo "==> 正在切换 ELRepo 为清华源镜像 (加速下载)..."
if [[ -f /etc/yum.repos.d/elrepo.repo ]]; then
  cp /etc/yum.repos.d/elrepo.repo /etc/yum.repos.d/elrepo.repo.bak
  sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/elrepo.repo
  sed -i 's|^#\?baseurl=http://elrepo.org/linux|baseurl=https://mirrors.tuna.tsinghua.edu.cn/elrepo|g' /etc/yum.repos.d/elrepo.repo
else
  echo "Error: elrepo.repo 文件未找到，安装失败。" >&2
  exit 1
fi

echo "==> 更新 Yum 缓存并安装 LTS 内核..."
yum makecache -y
yum -y --enablerepo=elrepo-kernel install kernel-lt kernel-lt-devel

echo "==> 正在重建 GRUB 引导配置..."
grub_cfg_path=""
if [[ -d /sys/firmware/efi ]]; then
  grub_cfg_path="/boot/efi/EFI/centos/grub.cfg"
  echo "识别为 UEFI 引导模式，输出路径: ${grub_cfg_path}"
  [[ -f "$grub_cfg_path" ]] || { echo "Error: 未找到 $grub_cfg_path（UEFI grub.cfg 路径可能不同）" >&2; exit 1; }
else
  grub_cfg_path="/boot/grub2/grub.cfg"
  echo "识别为 BIOS 引导模式，输出路径: ${grub_cfg_path}"
  [[ -f "$grub_cfg_path" ]] || { echo "Error: 未找到 $grub_cfg_path" >&2; exit 1; }
fi

grub2-mkconfig -o "$grub_cfg_path" >/dev/null

echo "==> 设置新内核为默认启动项..."
# 从 grub.cfg 中挑选第一个包含 "kernel-lt" 的 menuentry（更可靠）
default_entry="$(
  awk -F"'" '/^menuentry /{print $2}' "$grub_cfg_path" | grep -m1 'kernel-lt' || true
)"
if [[ -z "$default_entry" ]]; then
  echo "Error: 未在 grub 配置中找到包含 kernel-lt 的启动项，无法设置默认。" >&2
  exit 1
fi
grub2-set-default "$default_entry"

echo "----------------------------------------"
echo "内核安装完成！"
echo "默认引导项（grub2-editenv list）:"
grub2-editenv list || true
echo "已设置默认启动项为: $default_entry"
echo "请手动重启服务器以生效: reboot"
echo "----------------------------------------"
