#!/usr/bin/env bash
script_file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/ops/proc-watch-list.sh"
# shellcheck source=ops/proc-watch-list.sh
source "$script_file"
set -uo pipefail

test_dir=$(mktemp -d)
test_dir=$(cd -- "$test_dir" && pwd -P)
trap 'rm -rf -- "$test_dir"' EXIT
failures=0

fail() { printf '%s\n' "$*" >&2; return 1; }
assert_equal() { [[ "$1" == "$2" ]] || fail "期望 [$2]，实际 [$1]"; }
assert_rejected() {
  if "$@"; then fail "应拒绝：$*"; fi
}
fixture_process() {
  local root=$1 pid=$2 cwd=$3
  shift 3
  mkdir -p "$root/$pid"
  printf '%s\0' "$@" >"$root/$pid/cmdline"
  ln -s "$cwd" "$root/$pid/cwd"
}
wait_ready() {
  local attempt
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ ! -f "$1" ]] || return 0
    sleep 0.01
  done
  fail "等待超时：$1"
}
make_worker() {
  mkdir -p "$1"
  printf '#!/bin/sh\nexit 0\n' >"$1/worker"
  chmod +x "$1/worker"
}
install_launcher() {
  mkdir -p "$case_dir/bin"
  export TEST_CASE_DIR="$case_dir" TEST_PROGRAM_DIR="$1" TEST_QUIET="${2:-0}"
  export PATH="$case_dir/bin:$PATH"
  cat >"$case_dir/bin/setsid" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$PWD" == "$TEST_PROGRAM_DIR" ]] || : >"$TEST_CASE_DIR/failure"
if read -r _; then : >"$TEST_CASE_DIR/failure"; fi
[[ ! -e /dev/fd/9 && ! -e /dev/fd/8 && ! -e /dev/fd/7 ]] || : >"$TEST_CASE_DIR/failure"
if (( TEST_QUIET )); then
  [[ /dev/fd/1 -ef /dev/null && /dev/fd/2 -ef /dev/null ]] || : >"$TEST_CASE_DIR/failure"
fi
printf '%s\0' "$@" >"$TEST_CASE_DIR/args"
printf 'launch\n' >>"$TEST_CASE_DIR/count"
printf 'stdout\n'
printf 'stderr\n' >&2
: >"$TEST_CASE_DIR/ready"
LAUNCHER
  chmod +x "$case_dir/bin/setsid"
}
# 测试中的 stat 适配 macOS，生产仍明确使用 GNU stat。
stat() { wc -c <"${@: -1}"; }

case_parser() {
  parse_entry "/root/prom/node-exporter --collector.filesystem.ignored-mount-points='^/(sys|proc|dev|run)(\$|/)' &> /dev/null"
  assert_equal "${#PARSED_ARGV[@]}" 2
  assert_equal "$PARSED_DISCARD" 1
  assert_equal "${PARSED_ARGV[1]}" '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|run)($|/)'
  parse_entry "/bin/worker \"two words\" '' \"\" key='a|b' \"&> /dev/null\""
  assert_equal "${#PARSED_ARGV[@]}" 6
  assert_equal "$PARSED_DISCARD" 0
  assert_equal "${PARSED_ARGV[1]}" 'two words'
  assert_equal "${PARSED_ARGV[2]}" ''
  assert_equal "${PARSED_ARGV[3]}" ''
  assert_equal "${PARSED_ARGV[4]}" 'key=a|b'
  assert_equal "${PARSED_ARGV[5]}" '&> /dev/null'
  parse_entry '/bin/worker "a\"b" "c\\d" "e\q"'
  assert_equal "${PARSED_ARGV[1]}" 'a"b'
  assert_equal "${PARSED_ARGV[2]}" 'c\d'
  assert_equal "${PARSED_ARGV[3]}" 'e\q'
  parse_entry $'/bin/worker\targ &>/dev/null\t\r'
  assert_equal "$PARSED_DISCARD" 1
  assert_equal "${PARSED_ARGV[1]}" arg
  parse_entry $' \t# comment " | >'
  assert_equal "${#PARSED_ARGV[@]}" 0
  parse_entry '   '
  assert_equal "${#PARSED_ARGV[@]}" 0
}

case_parser_rejects() {
  local invalid
  for invalid in "/bin/worker 'unclosed" '/bin/worker "unclosed' \
    '/bin/worker > /tmp/out' '/bin/worker | cat' '/bin/worker < /dev/null' \
    '/bin/worker &> /tmp/out' '/bin/worker &> /dev/null extra' \
    '/bin/worker &> /dev/null; touch /tmp/injected' '/bin/worker&>/dev/null' \
    '/bin/worker &> "/dev/null"' '&> /dev/null'; do
    assert_rejected parse_entry "$invalid"
    [[ -n "$PARSE_ERROR" ]]
  done
}

case_literal_arguments() {
  parse_entry "/bin/worker '\$(touch $case_dir/injected)' '\`touch $case_dir/injected\`' \"\$HOME\" https://host/job?a=[1]* a;false path\\name"
  assert_equal "${PARSED_ARGV[1]}" "\$(touch $case_dir/injected)"
  assert_equal "${PARSED_ARGV[2]}" "\`touch $case_dir/injected\`"
  assert_equal "${PARSED_ARGV[3]}" "\$HOME"
  assert_equal "${PARSED_ARGV[4]}" 'https://host/job?a=[1]*'
  assert_equal "${PARSED_ARGV[5]}" 'a;false'
  assert_equal "${PARSED_ARGV[6]}" 'path\name'
  [[ ! -e "$case_dir/injected" ]]
}

case_matching() {
  local root="$case_dir/proc" directory="$case_dir/one"
  fixture_process "$root" 101 "$directory" "$directory/worker" 'a b' '?[1]*' ''
  process_exists "$root" "$directory" 0 "$directory/worker" 'a b' '?[1]*' ''
  assert_rejected process_exists "$root" "$directory" 0 "$directory/worker" a b '?[1]*' ''
  assert_rejected process_exists "$root" "$directory" 0 "$directory/worker" 'a b' '?[1]*'
  assert_rejected process_exists "$root" "$directory" 0 "$case_dir/two/worker" 'a b' '?[1]*' ''
  fixture_process "$root" 102 "$directory" ./worker relative
  process_exists "$root" "$directory" 0 "$directory/worker" relative
  assert_rejected process_exists "$root" "$case_dir/two" 0 "$case_dir/two/worker" relative
  fixture_process "$root" 103 "$directory" /bin/bash "$directory/worker" script
  process_exists "$root" "$directory" 1 "$directory/worker" script
  assert_rejected process_exists "$root" "$directory" 0 "$directory/worker" script
  fixture_process "$root" 104 "$directory" /bin/bash -e ./worker flags
  process_exists "$root" "$directory" 1 "$directory/worker" flags
  # 空 cmdline（僵尸/内核线程）以及扫描中消失的进程都不算匹配。
  mkdir -p "$root/105" "$root/106"
  : >"$root/105/cmdline"
  assert_rejected process_exists "$root" "$directory" 1 "$directory/worker" absent
}

case_launch() {
  local directory="$case_dir/program dir" log="$case_dir/watch.log" pid
  make_worker "$directory"
  install_launcher "$directory"
  exec 9>"$case_dir/lock" 8<"$directory/worker"
  launch_process "$directory" "$directory/worker.log" "$log" test "$directory/worker" 'two words' '' '*'
  pid=$!
  wait_ready "$case_dir/ready"
  wait "$pid"
  [[ ! -f "$case_dir/failure" ]]
  printf '%s\0' nohup "$directory/worker" 'two words' '' '*' >"$case_dir/expected"
  cmp "$case_dir/expected" "$case_dir/args"
  assert_equal "$(cat "$directory/worker.log")" $'stdout\nstderr'
  [[ "$(cat "$log")" == *'已请求启动'* ]]
  assert_rejected launch_process "$directory" "$case_dir/missing/out" "$log" test "$directory/worker"
  assert_equal "$(wc -l <"$case_dir/count" | tr -d ' ')" 1
}

case_quiet() {
  make_worker "$case_dir/service"
  install_launcher "$case_dir/service" 1
  printf "%s --regex='^/(sys|proc)(\$|/)' &> /dev/null\n" "$case_dir/service/worker" >"$case_dir/list"
  check_once "$case_dir/list" "$case_dir/watch.log" 100000 "$case_dir/proc"
  wait_ready "$case_dir/ready"
  wait
  [[ ! -f "$case_dir/service/worker.log" && ! -f "$case_dir/failure" ]]
  printf '%s\0' nohup "$case_dir/service/worker" '--regex=^/(sys|proc)($|/)' >"$case_dir/expected"
  cmp "$case_dir/expected" "$case_dir/args"
}

case_configuration() {
  make_worker "$case_dir/service"
  install_launcher "$case_dir/service"
  # 错误配置后继续，CRLF、末行无换行、引号不同但 argv 相同的重复项。
  printf ' # comment\r\n/missing/worker\r\n%s "unclosed\n%s '\''arg'\''\r\n%s "arg"' \
    "$case_dir/service/worker" "$case_dir/service/worker" "$case_dir/service/worker" >"$case_dir/list"
  check_once "$case_dir/list" "$case_dir/watch.log" 100000 "$case_dir/proc"
  wait
  assert_equal "$(wc -l <"$case_dir/count" | tr -d ' ')" 1
  # 每轮重新读配置；已有进程不重复启动。
  fixture_process "$case_dir/proc" 201 "$case_dir/service" /bin/sh "$case_dir/service/worker" next
  printf '%s next\n' "$case_dir/service/worker" >"$case_dir/list"
  check_once "$case_dir/list" "$case_dir/watch.log" 100000 "$case_dir/proc"
  wait
  assert_equal "$(wc -l <"$case_dir/count" | tr -d ' ')" 1
  assert_rejected check_once "$case_dir/missing" "$case_dir/watch.log" 100000 "$case_dir/proc"
}

case_rotation() {
  local file="$case_dir/program.log" log="$case_dir/watch.log"
  printf 123456 >"$file"
  exec 6>>"$file"
  rotate_log "$file" 4 "$log"
  assert_equal "$(cat "$file.bak")" 123456
  [[ ! -s "$file" ]]
  printf abcdef >&6
  assert_equal "$(cat "$file")" abcdef
  rotate_log "$file" 4 "$log"
  assert_equal "$(cat "$file.bak")" abcdef
  [[ ! -s "$file" ]]
  # 恰好达到阈值不轮转，守护日志也保留一个备份。
  printf 1234 >"$file"
  rotate_log "$file" 4 "$log"
  assert_equal "$(cat "$file")" 1234
  rotate_log "$log" 4 "$log"
  [[ -s "$log.bak" && -s "$log" ]]
  # 无法备份时保持原日志；全局日志故障明确返回 2。
  mkdir "$case_dir/bad.log.bak"
  printf 123456 >"$case_dir/bad.log"
  assert_rejected rotate_log "$case_dir/bad.log" 4 "$log"
  assert_equal "$(cat "$case_dir/bad.log")" 123456
  # shellcheck disable=SC2329
  cp() { return 1; }
  printf 123456 >"$case_dir/copy-failure.log"
  assert_rejected rotate_log "$case_dir/copy-failure.log" 4 "$log"
  assert_equal "$(cat "$case_dir/copy-failure.log")" 123456
  local status=0
  log_event "$case_dir/missing/watch.log" test || status=$?
  assert_equal "$status" 2
}

case_error_isolation() {
  make_worker "$case_dir/bad"
  make_worker "$case_dir/good"
  mkdir "$case_dir/bad/worker.log"
  install_launcher "$case_dir/good"
  printf '%s\n' "$case_dir/bad/worker" "$case_dir/good/worker" >"$case_dir/list"
  check_once "$case_dir/list" "$case_dir/watch.log" 100000 "$case_dir/proc"
  wait
  assert_equal "$(wc -l <"$case_dir/count" | tr -d ' ')" 1
  [[ "$(cat "$case_dir/watch.log")" == *'程序日志轮转失败'* ]]
  mkdir "$case_dir/log-directory"
  local status=0
  check_once "$case_dir/list" "$case_dir/log-directory" 100000 "$case_dir/proc" || status=$?
  assert_equal "$status" 2
}

case_arguments() {
  local invalid
  for invalid in 0 000 -1 1.5 abc; do assert_rejected main "$invalid"; done
  assert_rejected main 3 extra
}

case_main_lifecycle() {
  command cp "$script_file" "$case_dir/watcher.sh"
  : >"$case_dir/proc-watch-list.txt"
  export TEST_CASE_DIR="$case_dir"
  cat >"$case_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
# shellcheck source=/dev/null
source "$TEST_CASE_DIR/watcher.sh"
# 主循环的跨平台测试；真实 flock 和 /proc 联调须在 Linux 执行。
require_runtime() { return 0; }
flock() { [[ ! -e "$TEST_CASE_DIR/deny-lock" ]]; }
check_once() { : >"$TEST_CASE_DIR/ready"; }
main 30
HARNESS
  bash "$case_dir/harness.sh" &
  local daemon_pid=$! attempt
  trap 'kill "$daemon_pid" 2>/dev/null || :' EXIT
  wait_ready "$case_dir/ready"
  [[ -f "$case_dir/proc-watch-list.lock" ]]
  kill -TERM "$daemon_pid"
  for ((attempt = 0; attempt < 200; attempt++)); do
    kill -0 "$daemon_pid" 2>/dev/null || break
    sleep 0.01
  done
  if kill -0 "$daemon_pid" 2>/dev/null; then fail '守护未及时响应 TERM'; fi
  wait "$daemon_pid"
  # 锁获取失败应在首轮检查之前退出。
  : >"$case_dir/deny-lock"
  mv "$case_dir/ready" "$case_dir/previous-ready"
  assert_rejected bash "$case_dir/harness.sh"
  [[ ! -f "$case_dir/ready" ]]
  trap - EXIT
}

for test_case in case_parser case_parser_rejects case_literal_arguments case_matching \
  case_launch case_quiet case_configuration case_rotation case_error_isolation case_arguments case_main_lifecycle; do
  case_dir="$test_dir/$test_case"
  mkdir -p "$case_dir"
  # 父进程收集结果，子进程启用 errexit；不要将子进程放入 if 条件。
  (set -e; "$test_case") >"$case_dir/output" 2>&1
  result=$?
  if (( result == 0 )); then
    printf 'PASS %s\n' "$test_case"
  else
    printf 'FAIL %s\n' "$test_case" >&2
    cat "$case_dir/output" >&2
    failures=$((failures + 1))
  fi
done
(( failures == 0 ))
