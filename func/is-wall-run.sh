#!/bin/bash
# 墙内则执行一组命令
# 接受全部参数，当作一条命令执行，参数为空不做任何操作

# function is_wall_run_old(){
#   if [[ "$*" ]] && ! ping -c 1 google.com ; then
#     eval "$*"
#   fi
# }
# is_wall_run "$*"

# 注意，接受每个参数当作一条命令行执行
# 多命令 is_wall_run 'cmd1' 'cmd2' 方式
function is_wall_run(){
  if ! ping -c 1 google.com ; then
    for e in "$@" ; do
      eval $e
    done
  fi
}
is_wall_run "$@"
