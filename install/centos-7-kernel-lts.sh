#!/bin/bash
# 安装 CentOS 7 ELRepo LTS 内核
# 自动适配 BIOS 和 UEFI 引导模式
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/centos-7-kernel-lts.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/install/centos-7-kernel-lts.sh)"

set -euo pipefail

# 1. 权限与环境检查
if [[ $EUID -ne 0 ]]; then
   echo "Error: 本脚本需要 Root 权限执行。"
   exit 1
fi

if ! grep -q "CentOS Linux 7" /etc/redhat-release; then
    echo "Error: 本脚本仅支持 CentOS 7 系统。"
    exit 1
fi

echo "==> 正在安装 ELRepo Release 包..."
# 使用 rpm -Uvh 替代 yum install，避免 yum 锁或源元数据同步造成的干扰
yum install -y --nogpgcheck https://mirrors.tuna.tsinghua.edu.cn/elrepo/elrepo/el7/x86_64/RPMS/elrepo-release-7.0-8.el7.elrepo.noarch.rpm || true
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-elrepo.org

echo "==> 正在切换 ELRepo 为清华源镜像 (加速下载)..."
if [ -f /etc/yum.repos.d/elrepo.repo ]; then
    cp /etc/yum.repos.d/elrepo.repo /etc/yum.repos.d/elrepo.repo.bak
    # 更加严谨的 sed 替换，防止多次执行导致 URL 畸形
    sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/elrepo.repo
    sed -i 's|^#\?baseurl=http://elrepo.org/linux|baseurl=https://mirrors.tuna.tsinghua.edu.cn/elrepo|g' /etc/yum.repos.d/elrepo.repo
else
    echo "Error: elrepo.repo 文件未找到，安装失败。"
    exit 1
fi

echo "==> 更新 Yum 缓存并安装 LTS 内核..."
yum makecache
# 仅安装 lt (Long Term) 版本
yum -y --enablerepo=elrepo-kernel install kernel-lt kernel-lt-devel

echo "==> 正在重建 GRUB 引导配置..."
# 2. 核心优化：动态识别 BIOS/UEFI 路径
if [ -d /sys/firmware/efi ]; then
    grub_cfg_path="/boot/efi/EFI/centos/grub.cfg"
    echo "识别为 UEFI 引导模式，输出路径: $grub_cfg_path"
else
    grub_cfg_path="/boot/grub2/grub.cfg"
    echo "识别为 BIOS 引导模式，输出路径: $grub_cfg_path"
fi

# 重建配置
grub2-mkconfig -o "$grub_cfg_path"

echo "==> 设置新内核为默认启动项..."
# 强制设置索引 0 为默认 (新安装内核通常位于最顶端)
grub2-set-default 0

# 3. 结果验证
current_default=$(grub2-editenv list)
echo "----------------------------------------"
echo "内核安装完成！"
echo "当前默认引导项: $current_default"
echo "请手动重启服务器以生效: reboot"
echo "----------------------------------------"
