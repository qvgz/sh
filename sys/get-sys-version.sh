#!/usr/bin/env bash
# 系统版本
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/sys/get-sys-version.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/sys/get-sys-version.sh)"

sys_version=$(grep 'VERSION_CODENAME' /etc/os-release | awk -F '=' '{print $2}')
echo $sys_version

