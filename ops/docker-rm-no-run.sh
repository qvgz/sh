#!/usr/bin/env bash
# 删除未运行容器与卷
# $1 为排除容器相关字符
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/docker-rm-no-run.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/docker-rm-no-run.sh)"

# docker_ps_all=$(docker ps -a | cut -d ' ' -f1 | sed 's/CONTAINER//') # 换行存储到字符串变成了空格
# docker_ps_quiet=$(docker ps --quiet)

# # 剔除在运行
# for e in $docker_ps_quiet ; do
#   docker_ps_all=$(echo $docker_ps_all | sed "s/$e//")
# done

# docker rm $docker_ps_all
# docker volume prune

set -e


if [[ -z "$1" ]]; then
  rm_str=$(docker ps -a | grep 'Exited')
else
  rm_str=$(docker ps -a | grep 'Exited' | grep -v $1)
fi


echo "$rm_str"

echo -ne "\033[31m任意键执行删除(docker rm -vf)，退出输入 n|no：\033[0m"
read -r yn
if [[ $yn == "n" || $yn == "no" ]] ; then
  exit 0
fi
read -ra rm_id <<< "$( echo "$rm_str" | awk '{print $1}' | xargs)"
docker rm -v "${rm_id[@]}" > /dev/null
