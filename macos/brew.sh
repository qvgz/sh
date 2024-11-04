#!/usr/bin/env bash
# 记录 macOS 中 brew 应用
# 环境变量 $BREW_LIST_PATH 指定 brew-list 路径，缺省在 brew.sh 同目录中
# 注意使用 gnu-sed
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/macos/brew.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/macos/brew.sh)"

set -e

all=$*
cmd="${all%% *}"
apps="${all#* }"

if [[ ${BREW_LIST_PATH} == "" ]];then
    BREW_LIST_PATH="$(dirname ${BASH_SOURCE[0]})/brew-list"
fi

 args=""
case $cmd in
    install)
        for app in $apps;do
            # -- 开头为参数
            if [[ $app =~ ^--.* ]];then
                args+="$app "
            else
                eval /opt/homebrew/bin/brew install ${args}${app} && echo "$app" >> $BREW_LIST_PATH
            fi
        done
        tmpfile=$(mktemp)
        sort $BREW_LIST_PATH > $tmpfile
        mv $tmpfile $BREW_LIST_PATH
    ;;
    uninstall)
         for app in $apps;do
            # -- 开头为参数
            if [[ $app =~ ^--.* ]] ;then
                  args+="$app "
            else
                 eval /opt/homebrew/bin/brew uninstall ${args}${app}
                 /opt/homebrew/opt/gnu-sed/libexec/gnubin/sed -i "/$app/d" $BREW_LIST_PATH
            fi
        done
    ;;
    *)
        # 执行失败，脚本停止，执行成功脚本退出
        eval brew "$*"
esac
