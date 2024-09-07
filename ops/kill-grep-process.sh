#!/usr/bin/env bash
# 筛选杀死进程
# $1 指定字符串进程
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/kill-grep-process.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/ops/kill-grep-process.sh)"

# grep_str=$1

# if [[ $grep_str == '' ]] ;then
#     read -rp "输入字符串将杀死相关进程：" str
# fi

# oldifs=$IFS
# IFS=$'\n'
# for e in $(ps aux | grep $grep_str);do
#     if [[ $(echo $e | awk '{print $11}') == "$grep_str" ]] ; then
#         for e2 in $(echo $e | awk '{print $2}');do
#             kill $e2
#         done
#     fi
# done
# IFS=$oldifs

set -e

for e in $(pidof $1) ; do
    kill $e
done
