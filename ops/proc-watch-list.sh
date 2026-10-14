#!/usr/bin/env bash
# Linux 进程列表守护
# 解析器的输出仅有 PARSED_ARGV、PARSED_DISCARD 和 PARSE_ERROR。
# 不使用 eval/bash -c，不执行任何 shell 展开。

declare -A restart_failures=() restart_pending=()

parse_entry() {
  local text=${1%$'\r'} quote='' word='' active=0 index char next suffix
  PARSED_ARGV=()
  PARSED_DISCARD=0
  PARSE_ERROR=''

  for ((index = 0; index < ${#text}; index++)); do
    char=${text:index:1}
    if [[ -n "$quote" ]]; then
      if [[ "$char" == "$quote" ]]; then
        quote=''
      elif [[ "$quote" == '"' && "$char" == \\ ]]; then
        next=${text:index+1:1}
        if [[ "$next" == '"' || "$next" == \\ ]]; then
          word+=$next
          index=$((index + 1))
        else
          word+=$char
        fi
      else
        word+=$char
      fi
      continue
    fi

    case "$char" in
      ' '|$'\t')
        if (( active )); then
          PARSED_ARGV+=("$word")
          word=''
          active=0
        fi
        ;;
      "'"|'"') quote=$char; active=1 ;;
      '<'|'>'|'|')
        PARSE_ERROR='不支持的重定向或管道'
        return 1
        ;;
      '&')
        if [[ "${text:index:2}" == '&>' ]]; then
          suffix=${text:index}
          if (( !active && ${#PARSED_ARGV[@]} > 0 )) &&
            [[ "$suffix" =~ ^\&\>[[:blank:]]*/dev/null[[:blank:]]*$ ]]; then
            PARSED_DISCARD=1
            return 0
          fi
          PARSE_ERROR='仅支持独立的行尾 &> /dev/null'
          return 1
        fi
        word+=$char; active=1
        ;;
      '#')
        if (( !active && ${#PARSED_ARGV[@]} == 0 )); then return 0; fi
        word+=$char; active=1
        ;;
      *) word+=$char; active=1 ;;
    esac
  done

  if [[ -n "$quote" ]]; then
    PARSE_ERROR='引号未闭合'
    return 1
  fi
  if (( active )); then PARSED_ARGV+=("$word"); fi
  return 0
}

log_event() {
  local file=$1 timestamp
  shift
  timestamp=$(date +'%Y-%m-%d %H:%M:%S') || return 2
  if ! printf '%s %s\n' "$timestamp" "$*" >>"$file"; then
    printf '守护日志写入失败：%s\n' "$file" >&2
    return 2
  fi
}

rotate_log() {
  local file=$1 limit=$2 log=$3 size
  [[ -e "$file" ]] || return 0
  [[ -f "$file" ]] || return 1
  size=$(stat -c %s -- "$file") || return 1
  [[ "$size" =~ ^[0-9]+$ ]] || return 1
  (( size > limit )) || return 0
  [[ ! -d "$file.bak" ]] || return 1
  # 保留原 inode，业务进程的输出 FD 在轮转后继续有效。
  cp -f -- "$file" "$file.bak" && : >"$file" || return 1
  log_event "$log" "清理 $file"
}

# 从 NUL 分隔的 cmdline 比较参数，不将参数拼成字符串或正则。
# 0=匹配，1=不匹配/进程已退出。所有状态都通过参数传入。
process_matches() {
  local proc=$1 directory=$2 script=$3 value offset index candidate
  shift 3
  local -a actual=() expected=("$@")
  [[ -r "$proc/cmdline" ]] || return 1
  while IFS= read -r -d '' value; do
    actual+=("$value")
  done 2>/dev/null <"$proc/cmdline" || return 1

  offset=$((${#actual[@]} - ${#expected[@]}))
  (( offset >= 0 && offset <= 2 )) || return 1
  (( offset == 0 || script )) || return 1
  candidate=${actual[offset]}
  if [[ "$candidate" != "${expected[0]}" ]]; then
    [[ "$candidate" == "./${expected[0]##*/}" ]] || return 1
    [[ "$(readlink -- "$proc/cwd" 2>/dev/null)" == "$directory" ]] || return 1
  fi
  for ((index = 1; index < ${#expected[@]}; index++)); do
    [[ "${actual[index + offset]}" == "${expected[index]}" ]] || return 1
  done
  return 0
}

process_exists() {
  local root=$1 directory=$2 script=$3 proc
  shift 3
  for proc in "$root"/[0-9]*; do
    process_matches "$proc" "$directory" "$script" "$@" && return 0
  done
  return 1
}

launch_process() {
  local directory=$1 output=$2 log=$3 label=$4 pid
  shift 4
  # 在父进程中打开输出，打开失败时不会记录为已提交启动。
  exec 7>>"$output" || return 1
  (
    # 子进程不持有输出副本、配置文件或实例锁。
    exec 7>&- 8<&- 9>&-
    cd -- "$directory" || exit 1
    exec setsid nohup "$@"
  ) </dev/null >&7 2>&1 &
  pid=$!
  exec 7>&-
  log_event "$log" "已请求启动 pid=$pid：$label"
}

# 每轮独立解析配置；seen 按规范化 argv 去重，保留第一条的输出设置。
# 1=配置读取失败；2=守护日志失败；单条配置故障记录后继续。
check_once() {
  local config=$1 log=$2 limit=$3 proc_root=$4
  local line number=0 executable directory name output magic script key status exists failures
  local -a argv=()
  local -A seen=()

  rotate_log "$log" "$limit" "$log" || return 2
  : >>"$log" || return 2
  # 配置使用独立 FD，业务进程 stdin 永远不读取此文件。
  [[ -f "$config" && -r "$config" ]] || return 1
  exec 8<"$config" || return 1
  while IFS= read -r line <&8 || [[ -n "$line" ]]; do
    number=$((number + 1))
    line=${line%$'\r'}
    if ! parse_entry "$line"; then
      log_event "$log" "第 $number 行跳过：$PARSE_ERROR" || { exec 8<&-; return 2; }
      continue
    fi
    (( ${#PARSED_ARGV[@]} > 0 )) || continue
    argv=("${PARSED_ARGV[@]}")
    executable=${argv[0]}
    if [[ "$executable" != /* || ! -f "$executable" || ! -x "$executable" ]]; then
      log_event "$log" "第 $number 行跳过：需要可执行普通文件的绝对路径：$executable" || { exec 8<&-; return 2; }
      continue
    fi
    name=${executable##*/}
    if ! directory=$(cd -- "${executable%/*}/" && pwd -P); then
      log_event "$log" "第 $number 行失败：无法进入程序目录" || { exec 8<&-; return 2; }
      continue
    fi
    argv[0]="${directory%/}/$name"
    printf -v key '%q ' "${argv[@]}"
    [[ -z "${seen[$key]:-}" ]] || continue
    seen[$key]=1

    script=0
    magic=''
    if IFS= read -r -N 2 magic <"${argv[0]}" && [[ "$magic" == '#!' ]]; then script=1; fi
    exists=0
    failures=${restart_failures[$key]:-0}
    if process_exists "$proc_root" "$directory" "$script" "${argv[@]}"; then
      exists=1
      if (( failures > 0 )); then
        log_event "$log" "进程已恢复，连续重启失败次数清零（原 $failures 次）：$line" || { exec 8<&-; return 2; }
      fi
      restart_failures[$key]=0
      restart_pending[$key]=0
    elif [[ "${restart_pending[$key]:-0}" == 1 ]]; then
      failures=$((failures + 1))
      restart_failures[$key]=$failures
      restart_pending[$key]=0
      log_event "$log" "重启失败（连续 $failures 次，下轮检查进程仍不存在）：$line" || { exec 8<&-; return 2; }
      if (( failures >= 3 )); then
        log_event "$log" "连续 3 次重启失败，停止尝试重启，继续检查恢复：$line" || { exec 8<&-; return 2; }
      fi
    fi
    output="${directory%/}/$name.log"
    if (( PARSED_DISCARD )); then
      output=/dev/null
    else
      status=0
      rotate_log "$output" "$limit" "$log" || status=$?
      if (( status != 0 )); then
        if (( status == 2 )); then exec 8<&-; return 2; fi
        log_event "$log" "第 $number 行失败：程序日志轮转失败：$output" || { exec 8<&-; return 2; }
        continue
      fi
    fi
    if (( exists || failures >= 3 )); then continue; fi
    status=0
    launch_process "$directory" "$output" "$log" "第 $number 行 $line" "${argv[@]}" || status=$?
    if (( status == 2 )); then exec 8<&-; return 2; fi
    if (( status != 0 )); then
      failures=$((failures + 1))
      restart_failures[$key]=$failures
      log_event "$log" "第 $number 行重启失败（连续 $failures 次）：无法打开程序输出：$output" || { exec 8<&-; return 2; }
      if (( failures >= 3 )); then
        log_event "$log" "连续 3 次重启失败，停止尝试重启，继续检查恢复：$line" || { exec 8<&-; return 2; }
      fi
    else
      restart_pending[$key]=1
    fi
  done
  exec 8<&-
}

require_runtime() {
  local dependency
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 1) )) ||
    [[ ! -r /proc/self/cmdline ]]; then
    printf '需要 Linux、可读的 /proc 和 Bash 4.1+\n' >&2
    return 1
  fi
  for dependency in flock setsid nohup stat cp readlink date sleep; do
    if ! command -v "$dependency" >/dev/null; then
      printf '缺少命令：%s\n' "$dependency" >&2
      return 1
    fi
  done
}

main() {
  local interval=${1:-15} directory config log status sleeper=''
  local limit=$((512 * 1024 * 1024))
  if (( $# > 1 )) || [[ ! "$interval" =~ ^[0-9]+$ || ! "$interval" =~ [1-9] ]]; then
    printf '用法：%s [正整数检查间隔秒数，默认 15]\n' "$0" >&2
    return 1
  fi
  require_runtime || return 1
  directory=.
  if [[ "${BASH_SOURCE[0]}" == */* ]]; then directory=${BASH_SOURCE[0]%/*}; fi
  directory=$(cd -- "$directory" && pwd -P) || return 1
  config="$directory/proc-watch-list.txt"
  log="$directory/proc-watch-list.log"
  [[ -f "$config" && -r "$config" ]] || { printf '配置不可读：%s\n' "$config" >&2; return 1; }
  exec 9>"$directory/proc-watch-list.lock" || return 1
  if ! flock -n 9; then
    printf '无法取得实例锁，可能已有守护运行：%s\n' "$directory" >&2
    exec 9>&-
    return 1
  fi
  # 仅停止守护的等待任务，已启动的业务进程保持运行。
  trap 'if [[ -n "$sleeper" ]]; then kill "$sleeper" 2>/dev/null; fi; exit 0' INT TERM
  while true; do
    status=0
    check_once "$config" "$log" "$limit" /proc || status=$?
    if (( status != 0 )); then
      printf '守护检查失败（状态 %s），退出：%s\n' "$status" "$config" >&2
      exec 9>&-
      return 1
    fi
    sleep "$interval" 9>&- &
    sleeper=$!
    wait "$sleeper" || { exec 9>&-; return 1; }
    sleeper=''
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # 显式处理失败；不依赖 errexit，也避免旧 Bash 对空数组的 nounset 差异。
  set -o pipefail
  main "$@"
fi
