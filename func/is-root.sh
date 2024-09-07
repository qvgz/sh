#!/usr/bin/env bash
# 提示需 root 执行

function is_root() {
  # "$(id -nu)" != "root"

  if [[ '0' != $(id -u) ]]; then
    echo "当前用户不是 root 用户"
    exit 1
  fi
}
is_root
