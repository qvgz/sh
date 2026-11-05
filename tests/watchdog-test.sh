#!/bin/bash
# watchdog.sh 集成测试，需在 Linux 上运行（兼容 Bash 3.2）
src="$(cd "$(dirname "$0")/.." && pwd)/ops/watchdog.sh"
dir=$(mktemp -d) || exit 1
failures=0

cleanup() {
    [ -f "$dir/watchdog.lock" ] && kill "$guard" 2>/dev/null
    pkill -f "$dir/app" 2>/dev/null
    rm -rf "$dir"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
# wait_for 秒数 命令...：轮询直到命令成功
wait_for() {
    local i=0 limit=$(($1 * 10))
    shift
    while [ $i -lt $limit ]; do
        "$@" && return 0
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}
count() { pgrep -f -- "^/bin/bash $dir/app$1" | wc -l; }
running() { [ "$(count "$1")" -ge 1 ]; }

cp "$src" "$dir/watchdog.sh"
printf '#!/bin/bash\nwhile :; do sleep 1; done\n' >"$dir/app"
chmod +x "$dir/app"
for i in 1 2; do cp "$dir/app" "$dir/app$i"; done

# 空配置：0 个进程可正常运行
: >"$dir/watchdog.conf"
# set -m：模拟 cron/交互终端启动，守护本身不继承忽略 INT/QUIT
set -m
RETRY_INTERVAL=2 bash "$dir/watchdog.sh" 1 &
guard=$!
set +m
wait_for 3 grep -q '启动' "$dir/watchdog.log" 2>/dev/null || fail "空配置未启动"

# 重复实例被锁拒绝
bash "$dir/watchdog.sh" 1 2>/dev/null && fail "重复实例未被拒绝"

# 热加载：注释、空行、CRLF、错误行、前台命令、带 shell 语法的命令
printf '%s\n' \
    '# 注释' '' \
    "  $dir/app1|$dir/app1"$'\r' \
    "$dir/app2|cd $dir && $dir/app2 >/dev/null 2>&1 &" \
    'no-separator' \
    '|empty-pattern' \
    "^$dir/never|true" >"$dir/watchdog.conf"
wait_for 5 running 1 || fail "app1 未启动"
wait_for 5 running 2 || fail "app2 未启动"
grep -q '第 5 行跳过：缺少 |' "$dir/watchdog.log" || fail "未记录缺少分隔符"
grep -q '第 6 行跳过：匹配串或启动命令为空' "$dir/watchdog.log" || fail "未记录空匹配串"

# 存在时不重复启动
sleep 2
[ "$(count 1)" -eq 1 ] || fail "app1 重复启动：$(count 1)"

# 守护的后台启动不额外忽略 SIGINT(2)/SIGQUIT(3)；以测试 shell 自身为基准（容器 PID 1 可能已忽略）
sigign() { sed -n 's/^SigIgn:[[:space:]]*//p' "/proc/$1/status"; }
base=$(sigign $$)
app=$(sigign "$(pgrep -f -- "^/bin/bash $dir/app1")")
[ $((0x$app & 6)) -eq $((0x$base & 6)) ] || fail "业务进程额外忽略 INT/QUIT：SigIgn=$app 基准=$base"

# 被杀后在重试间隔后重新拉起
old=$(pgrep -f -- "^/bin/bash $dir/app1")
pkill -f -- "$dir/app1"
restarted() { running 1 && [ "$(pgrep -f -- "^/bin/bash $dir/app1")" != "$old" ]; }
wait_for 5 restarted || fail "app1 未重新拉起"
recovered() { [ "$(grep -c "进程已恢复（此前启动 1 次）: $dir/app1" "$dir/watchdog.log")" -ge 2 ]; }
wait_for 3 recovered || fail "未记录 app1 恢复"

# 启动后仍不存在：最多启动 3 次，停止日志只记一次
gaveup() { grep -qF "已启动 3 次仍不存在，停止启动，继续检查恢复: ^$dir/never" "$dir/watchdog.log"; }
wait_for 10 gaveup || fail "未记录停止启动"
sleep 3
[ "$(grep -F ": ^$dir/never" "$dir/watchdog.log" | grep -c 尝试启动)" -eq 3 ] || fail "never 启动次数不是 3"
[ "$(grep -F ": ^$dir/never" "$dir/watchdog.log" | grep -c 停止启动)" -eq 1 ] || fail "停止日志重复"

# 进程不持有锁：守护退出后锁可再次获取
kill "$guard"
wait "$guard"
flock -n "$dir/watchdog.lock" true || fail "业务进程持有守护锁"
running 1 || fail "守护退出后业务进程被停止"

if [ $failures -eq 0 ]; then echo "PASS"; else
    cat "$dir/watchdog.log"
    exit 1
fi
