#!/usr/bin/env bash
# 生成 README.md

proxy="https://proxy.qvgz.org/sh/"
github="https://github.com/qvgz/sh/blob/master/"

# 地址、注释
find install/* ops/* sys/* macos/* other/* -print0 | xargs -0 -I% awk 'FNR==1 {print FILENAME} NR==2' % | sed 's/#//g' > /tmp/README.data

# 生成
data="# cmd

一些 shell 脚本"
head=""
head_next=""
while IFS=$'\n';read -r path;read -r intro; do
    head_next=${path%%/*}
    file_name=${path##*/}
    if [[ "$head" != "$head_next" ]];then
        data="$data \n\n## $head_next\n\n| 文件名 | 介绍 |\n| :- | :- |"
    fi
    # conf
    if [[ $head_next == "conf" ]];then
        data="$data\n| [$file_name]($github$path) | [$file_name]($proxy$path) |"
    else
        data="$data\n| [$file_name]($github$path) | [$intro]($proxy$path) |"
    fi
    head=$head_next
done < /tmp/README.data

echo -e "$data" > README.md
