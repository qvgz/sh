#!/usr/bin/env bash
# debian apt 源
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/debian-mirrors.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/debian-mirrors.sh)"

set -e

sys_version=$(grep 'VERSION_CODENAME' /etc/os-release | awk -F '=' '{print $2}')

mirrors='deb.debian.org'
if ! ping -c 1 google.com &> /dev/null; then
  mirrors='mirrors.cloud.tencent.com'
fi

non_free="non-free"

if [[ $(grep -w VERSION_ID /etc/os-release | sed 's/[^0-9]//g') == "12" ]];then
  non_free="non-free non-free-firmware"
fi

sudo cp /etc/apt/sources.list /etc/apt/sources.list.b
sudo tee /etc/apt/sources.list <<< "deb https://${mirrors}/debian/ ${sys_version} main contrib $non_free
deb https://${mirrors}/debian/ ${sys_version}-updates main contrib $non_free
deb https://${mirrors}/debian/ ${sys_version}-backports main contrib $non_free
deb https://${mirrors}/debian-security ${sys_version}-security main contrib $non_free"

sudo apt update
