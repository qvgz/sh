#!/usr/bin/env bash
# 日志相关
# 注意日志主要三个标志：OK 正确、NO 错误、ADD 追加配置

# 正确绿色
function echo_ok(){
  echo -e "\033[32m$1\033[0m"
  sleep 1
}

# 错误红色
function echo_error(){
  echo -e "\033[31m$1\033[0m"
  sleep 1
}


# 提示黄色
function echo_point(){
  echo -e "\n\033[33m$1\033[0m"
  sleep 1
}

# 开始蓝色
function echo_start(){
  echo -e "\033[34m$1\033[0m"
  sleep 1
}

# 追加配置
function echo_add(){
  echo -e "\033[36m$1\033[0m"
  sleep 1
}

# 输出退出
function error_exit(){
  echo_error $1
  sleep 1
  exit 1
}

# 配置不存在才追加
# $1 配置字符串
# $2 要追加配置路径
# $3 日志文件路径，可选
function add_conf(){
  if [[ $(grep -w "$1" "$2") == '' ]] ; then # -w 全字符匹配
    echo_add "ADD $1 到 $2"
    cp $2 "$2.$(date +%Y%m%d%H%M%S).bak" && echo "$1" >> "$2"
    if [[ $3 != '' ]] ; then
      echo "ADD $1 到 $2" >> "$3"
    fi
  fi
}

# 日志输出
# $1 为日志文件路径
function echo_log_file(){
  while IFS=$'\n' read -r line ; do
      case ${line:0:2} in
        "OK") echo_ok $line ;;
        "NO") echo_error $line ;;
        "AD") echo_add $line ;;
        * ) echo_point $line ;;
      esac
  done < $1
}
