#!/usr/bin/env bash
# 生成密码
# $1 为指定位数，缺省为 10 位
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/func/create-passwd.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/func/create-passwd.sh)"

function create_passwd(){
  local num=$1
  local passwd
  if (( ${num:=10} < 4 )) ; then
    echo "密码位数至少为 4 位，数字 大写字符 标点符号"
    exit 1
  fi
  # 循环生成密码，直至生成符合要求密码
  while : ; do
    # tr -d 删除指定集 -c 反转
    passwd="$(strings /dev/urandom | tr -dc '[:print:]'  | head -c$num)"
    # 密码强度验证
    # 必须含有 数字 大小写字符 标点符号
    if [[ $(echo $passwd | sed 's/[[:digit:]]//') != "$passwd" && \
    $(echo $passwd | sed 's/[[:lower:]]//') != "$passwd" && \
    $(echo $passwd | sed 's/[[:upper:]]//') != "$passwd" && \
    $(echo $passwd | sed 's/[[:punct:]]//') != "$passwd" && \
    # 排除难终端分辨字符出现如 空格 等
    $(echo $passwd | sed "s/[ 0oO1Ilz29gb6\"'\`]//") == "$passwd" ]] ; then
      break
    fi
  done
  echo $passwd
}
create_passwd $1
