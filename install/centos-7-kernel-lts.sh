#!/usr/bin/env bash
# centos 7 安装长期支持内核
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/centos-7-kernel-lts.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/install/centos-7-kernel-lts.sh)"

set -e

sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
sudo yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm

sudo cp /etc/yum.repos.d/elrepo.repo /etc/yum.repos.d/elrepo.repo.bak
sudo sed -i "s/elrepo.org\/linux/mirrors.aliyun.com\/elrepo/g" /etc/yum.repos.d/elrepo.repo
sudo yum makecache

sudo yum -y --enablerepo=elrepo-kernel install kernel-lt kernel-lt-devel

sudo grub2-set-default 0
sudo grub2-mkconfig -o /etc/grub2.cfg

