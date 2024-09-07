#!/usr/bin/env bash
# 筛选删除容器
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/docker-rm-grep-str.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/ops/docker-rm-grep-str.sh)"

# $1 删选 str

set -e

grep_str=$1
if [[ -z $grep_str ]] ; then
  echo "请输入要删除的容器信息！"
  exit 1
fi

grep_out=$(docker ps| grep $grep_str)
if [[ -z $grep_out ]] ; then
  echo "没有找到 $grep_str 相关容器！"
  exit 0
fi

docker ps| grep $grep_str

echo -ne "\033[31m任意键执行删除(docker rm -vf)，退出输入 n|no：\033[0m"
read -r yn
if [[ $yn == "n" || $yn == "no" ]] ; then
  exit 0
fi
docker ps| grep $grep_str | awk '{print $1}' | xargs docker rm -vf > /dev/null
