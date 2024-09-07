#!/usr/bin/env bash
# 判断同意否
# 同意标准为 回车 y yes (大小写不限) 其他情况为 no
# 整个要执行的条目放置子函数 （），n 就不继续执行

function is_yes(){
  echo -ne '是否同意（yes/no）：'; read -r input
  if [[ ! 'yes' =~ $(echo $input | tr '[:upper:]' '[:lower:]') ]] ; then
    echo "以取消！"
    exit 1
  fi
}
is_yes
