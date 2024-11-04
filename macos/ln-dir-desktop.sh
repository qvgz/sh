#!/usr/bin/env bash
# 桌面创建当前目录快捷方式
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/macos/ln-dir-desktop.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/macos/ln-dir-desktop.sh)"

set -e

dir_path=$(pwd)
dir_name=${dir_path##*/}

user_name=$(who | grep console | awk '{print $1}')

ln -s "$dir_path" "/Users/${user_name}/Desktop/${dir_name}"
