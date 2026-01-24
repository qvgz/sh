#!/usr/bin/env bash
# 进程列表守护
# 守护进程的执行文件（绝对路径）与参数写入脚本文件同目录下 proc-watch-list.txt 文本
# 每一行为一个进程：/abs/path/to/bin arg1 arg2 ...
# 在进程所在目录执行文件，例如：setsid nohup process >> process.log 2>&1 &
# $1 为检查间隔时间，单位秒，缺省为 3
# 不支持配置重定向/管道（避免注入），默认输出重定向到 process.log
# process.log 保留 512M 大小，超过备份后重置，备份只保留 1 份

set -euo pipefail

path="$(cd -- "$(dirname -- "$0")" && pwd -P)"
daemon_list="${path}/proc-watch-list.txt"
test -r "$daemon_list" || exit 1

sleep_time="${1:-}"
case "$sleep_time" in ''|*[!0-9]*) sleep_time=3;; esac

log_limit=$((512*1024*1024))
log="${path}/proc-watch-list.log"

# 仅 Linux/CentOS：stat -c
stat_size() {
  stat -c %s "$1" 2>/dev/null
}

log_need_rotate() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local size
    size="$(stat_size "$f" || echo 0)"
    [[ "$size" -gt "$log_limit" ]]
  else
    return 1
  fi
}

# 关键修复：不用 pgrep 正则匹配 cmdline（URL 里 ? 等字符会导致误判）
# 改为 ps 输出完整命令行后做固定字符串整行匹配
escape_ere() {
  # 将字符串转义为 ERE 字面量，避免 pgrep 把 ? . ( ) [ ] 等当正则
  # ERE 元字符：. ^ $ * + ? ( ) [ ] { } | \
  printf '%s' "$1" | sed -e 's/[.[\^$*+?(){}|\\]/\\&/g'
}

cmd_exists() {
  local want="$1"
  local pat
  pat="$(escape_ere "$want")"
  # -f：匹配完整命令行；-x：要求整行精确匹配（配合已转义的 pat）
  pgrep -fx -- "$pat" >/dev/null 2>&1
}

while true; do
  if log_need_rotate "$log"; then
    \mv -f "$log" "$log.bak"
    echo "$(date +'%Y-%m-%d %H:%M') 清理 $log" >>"$log"
  fi

  # 兼容“文件末行无换行”
  while IFS= read -r process || test -n "${process:-}"; do
    # 空行或注释跳过
    if test -z "${process:-}" || test "${process:0:1}" = "#"; then
      continue
    fi

    # 不支持重定向/管道（避免注入）
    if echo "$process" | grep -Eq '[<>|]'; then
      echo "$process 跳过！不支持配置重定向或管道符号" >>"$log"
      continue
    fi

    process_path="$(echo "$process" | awk '{print $1}')"
    test -z "${process_path:-}" && continue

    (
      cd -- "$(dirname -- "$process_path")" >>"$log" 2>&1 || exit 0
      process_name="$(basename -- "$process_path")"

      # 进程日志轮转
      if log_need_rotate "${process_name}.log"; then
        \cp -f "${process_name}.log" "${process_name}.log.bak"
        :> "${process_name}.log"
        echo "$(date +'%Y-%m-%d %H:%M') 清理 ${process_name}.log" >>"$log"
      fi

      # 提取参数（不强行 xargs 重排）
      args="$(echo "$process" | awk '{for (i=2;i<=NF;i++) printf $i" ";}')"
      args="${args%% }"

      if [[ -z "${args:-}" ]]; then
        cmd="./$process_name"
      else
        cmd="./$process_name $args"
      fi

      # 存在性判断（固定字符串整行匹配）
      if ! cmd_exists "$cmd"; then
        if [[ ! -x "$process_name" ]]; then
          chmod +x "$process_name" >>"$log" 2>&1 || {
            echo "$(date +'%Y-%m-%d %H:%M') 启动失败（chmod 无权限）: $process" >>"$log"
            exit 0
          }
        fi
        (setsid nohup $cmd >> "${process_name}.log" 2>&1 &)
        echo "$(date +'%Y-%m-%d %H:%M') 启动 $process" >>"$log"
      fi
    )
  done < "$daemon_list"

  sleep "$sleep_time"
done
