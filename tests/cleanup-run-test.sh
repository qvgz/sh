#!/usr/bin/env bash
# cleanup-run.sh 测试：退出码、信号转发、进程组清理
set -uo pipefail
# 作业控制：后台作业不忽略 INT，便于测试 INT 转发。
set -m

script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/utils/cleanup-run.sh"
t=$(mktemp -d)
trap 'rm -rf -- "$t"' EXIT
failures=0

check() {
  local name=$1 want=$2 got=$3
  if [[ $got == "$want" ]]; then echo "ok   $name"; else
    echo "FAIL $name"; diff <(echo "$want") <(echo "$got"); failures=$((failures + 1)); fi
}
# 等待文件出现，最多 2 秒
wait_file() { local i; for ((i = 0; i < 20; i++)); do [[ -s $1 ]] && return; sleep 0.1; done; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo gone; }

bash "$script" 2>/dev/null; check "无参数返回 2" 2 $?
CLEANUP_RUN_GRACE=1.25 bash "$script" true 2>/dev/null; check "无效宽限返回 2" 2 $?
bash "$script" bash -c 'exit 3'; check "透传退出码" 3 $?
check "透传 stdin" hello "$(echo hello | bash "$script" cat)"

# 子命令结束后清理残留后代
bash "$script" bash -c "sleep 300 & echo \$! >'$t/gc1'"
check "正常退出清理后代" gone "$(alive "$(cat "$t/gc1")")"

# TERM：转发给进程组，并以 TERM 结束自身
bash "$script" bash -c "trap 'echo TERM >\"$t/sig2\"; exit' TERM; sleep 300 & echo \$! >'$t/gc2'; wait" &
p=$!; wait_file "$t/gc2"; kill -TERM "$p"; wait "$p"
check "TERM 返回 143" 143 $?
check "TERM 转发" TERM "$(cat "$t/sig2")"
check "TERM 清理后代" gone "$(alive "$(cat "$t/gc2")")"

# INT：原信号转发
bash "$script" bash -c "trap 'echo INT >\"$t/sig3\"; exit' INT; echo \$\$ >'$t/pid3'; sleep 300 & wait" &
p=$!; wait_file "$t/pid3"; kill -INT "$p"; wait "$p"
check "INT 返回 130" 130 $?
check "INT 转发" INT "$(cat "$t/sig3")"

# 忽略 TERM 的子命令在宽限期后被 KILL
CLEANUP_RUN_GRACE=0.3 bash "$script" bash -c "trap '' TERM; echo \$\$ >'$t/pid4'; sleep 300; :" &
p=$!; wait_file "$t/pid4"; start=$SECONDS; kill -TERM "$p"; wait "$p"
check "宽限后 KILL" "gone 0" "$(alive "$(cat "$t/pid4")") $((SECONDS - start))"

if ((failures)); then echo "失败 $failures 项"; exit 1; fi
echo "全部通过"
