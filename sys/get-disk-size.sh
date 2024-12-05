#!/bin/bash
# 磁盘大小
# $1 为磁盘名

function get_disk_size(){
  local disk_path=$1

  # 如果不带路径，则加上
  if [[ ! $disk_path =~ '/' ]] ; then
    disk_path="/dev/$disk_path"
  fi

  # 检查是否存在
  if [[ ! -e "$disk_path" ]] ; then
    echo "$disk_path 不存在" ; exit 1
  fi

  # 检查是整个磁盘，还是某分区
  if [[ $disk_path =~ [0-9] ]] ; then
    lsblk -P "$disk_path" | cut -d ' ' -f4 | cut -d '=' -f2 | sed 's/"//g'
  else
    lsblk -P "$disk_path" | cut -d ' ' -f4 | cut -d '=' -f2 | sed 's/"//g' | xargs | cut -d ' ' -f1
  fi
}
get_disk_size $1