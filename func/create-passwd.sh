#!/bin/bash
# 生成密码
# $1 为指定位数，缺省为 10 位
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/func/create-passwd.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/func/create-passwd.sh)"

function create_passwd(){
  local num=$1
  local passwd
  if (( ${num:=10} < 4 )) ; then
    echo "密码位数至少为 4 位，数字 大写字符 标点符号"
    exit 1
  fi

  # 定义字符集
  local digits="23456789"
  local lowercase="abcdefghijkmnpqrstuvwxyz"
  local uppercase="ABCDEFGHJKMNPQRSTUVWXYZ"
  local symbols="!@#$%^&*()-+=[]{}|;:,.<>?"
  local all_chars="${digits}${lowercase}${uppercase}${symbols}"

  # 确保每种字符至少出现一次
  passwd="$(fold -w1 <<< "${digits}" | shuf -n1)$(fold -w1 <<< "${lowercase}"| shuf -n1)$(fold -w1 <<< "${uppercase}" | shuf -n1)$(fold -w1 <<< "${symbols}"| shuf -n1)"
    
  # 填充剩余长度
  remaining_length=$((num - 4))
  if (( remaining_length > 0 )); then
      passwd+="$(fold -w1 <<< ${all_chars} | shuf -n"${remaining_length}" | tr -d '\n')"
  fi
  
  # 打乱密码顺序
  passwd="$(fold -w1 <<< ${passwd} | shuf | tr -d '\n')"
  echo $passwd
}
create_passwd $1
