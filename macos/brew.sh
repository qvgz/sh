#!/usr/bin/env bash
# 记录 macOS 中 brew 应用
# 环境变量 $BREW_LIST_PATH 指定 brew-list 路径，缺省在 brew.sh 同目录中
# 注意使用 gnu-sed
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/macos/brew.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/macos/brew.sh)"

set -e

all_p=$*
cmd="${all_p%% *}"
apps="${all_p#* }"

if [[ ${BREW_LIST_PATH} == "" ]];then
    BREW_LIST_PATH="$(dirname ${BASH_SOURCE[0]})/brew-list"
fi

case $cmd in
    install)
        for app in $apps;do
            # 字符串不为 -- 开头，且安装成功
            # "${string:0:2}" == "--"
            if [[ ! $app =~ ^--.* ]] && eval brew install $app;then
                echo "$app" >> $BREW_LIST_PATH
            fi
        done
        tmpfile=$(mktemp)
        sort $BREW_LIST_PATH > $tmpfile
        mv $tmpfile $BREW_LIST_PATH
    ;;
    uninstall)
         for app in $apps;do
            # 字符串不为 -- 开头，且卸载成功
            if [[ ! $app =~ ^--.* ]] && eval brew uninstall $app;then
                 /opt/homebrew/opt/gnu-sed/libexec/gnubin/sed -i "/$app/d" $BREW_LIST_PATH
            fi
        done
    ;;
    *)
        # 执行失败，脚本停止，执行成功脚本退出
        eval brew "$*"
esac
