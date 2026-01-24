#!/usr/bin/env bash
# 判断在墙内执行一组命令
# 注意：命令含有参数需要用引号将命令和参数包裹
# 示例：is_wall_run "ls -alh /tmp" "grep 'error' /var/log/syslog"

is_wall_run() {
  # 1) 无参数：无需探测
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  # 2) 依赖检查
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: 'curl' command not found." >&2
    return 3
  fi

  # 3) 网络探测：增加总超时，避免挂住
  if ! curl -Is --connect-timeout 3 --max-time 5 https://www.google.com >/dev/null 2>&1; then
    local rc=1
    local cmd

    # 4) 执行命令：保持“传入字符串命令”的用法，但避免 eval
    # 使用 bash -lc：仍支持管道/重定向/引号等 shell 语法
    for cmd in "$@"; do
      if ! bash -lc "$cmd"; then
        rc=2
      fi
    done
    return "$rc"
  fi

  return 0
}

is_wall_run "$@"
