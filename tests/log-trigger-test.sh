#!/usr/bin/env bash
# log-trigger.sh 测试，需 Linux（最低 CentOS 7.9：Bash 4.2、GNU tail/grep/sed）
set -uo pipefail

script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/ops/log-trigger.sh"
t=$(mktemp -d)
pid=
trap '[[ -n $pid ]] && kill "$pid" 2>/dev/null; rm -rf -- "$t"' EXIT
failures=0

check() {
    local name=$1 want=$2 got=$3
    if [[ $got == "$want" ]]; then echo "ok   $name"; else
        echo "FAIL $name: want=[$want] got=[$got]"; failures=$((failures + 1)); fi
}
fail_msg() { echo "FAIL $*"; failures=$((failures + 1)); }
lines() { [[ -f $1 ]] && wc -l <"$1" | tr -d ' ' || echo 0; }
# start 文件 匹配串 [HITS] [SUPPRESS] [WINDOW] [CMD]：后台启动并等待 tail 就绪
start() {
    FILE=$1 PATTERN=$2 HITS=${3:-1} SUPPRESS=${4:-60} WINDOW=${5:-60} \
        CMD=${6:-'echo "$MATCH_LINE" >>'"$t/out"'; echo noise'} bash "$script" >"$t/log" 2>&1 &
    pid=$!
    sleep 1.5
}
stop() { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=; sleep 1.5; rm -f -- "$t/out"; }

# 参数校验
env -u FILE PATTERN=a CMD=true bash "$script" 2>/dev/null; check "缺 FILE 返回 2" 2 $?
FILE=$t/f PATTERN='' CMD=true bash "$script" 2>/dev/null; check "缺 PATTERN 返回 2" 2 $?
FILE=$t/f PATTERN=$'a\n' CMD=true bash "$script" 2>/dev/null; check "PATTERN 含换行返回 2" 2 $?
FILE=$t/f PATTERN=a CMD='' bash "$script" 2>/dev/null; check "缺 CMD 返回 2" 2 $?
FILE=$t/f PATTERN=a CMD=true HITS=0 bash "$script" 2>/dev/null; check "HITS=0 返回 2" 2 $?
FILE=$t/f PATTERN=a CMD=true WINDOW=-1 bash "$script" 2>/dev/null; check "WINDOW 负数返回 2" 2 $?
FILE=$t/f PATTERN=a CMD=true TIMEOUT=x bash "$script" 2>/dev/null; check "TIMEOUT 非数字返回 2" 2 $?
FILE=$t/f PATTERN=a CMD=true SUPPRESS=x bash "$script" 2>/dev/null; check "SUPPRESS 非数字返回 2" 2 $?

# 只看新增行；通配符；正则特殊字符按字面；抑制
f=$t/a.log
echo 'ERROR old' >"$f"
start "$f" 'ERR*[db].fail?'
printf '%s\n' 'x ERROR [db].failX y' 'ERR [db]xfailX' >>"$f"
sleep 1
check "旧行不触发、通配命中、特殊字符字面" 'x ERROR [db].failX y' "$(cat "$t/out" 2>/dev/null)"
echo 'ERR [db].fail1' >>"$f"; sleep 1
check "抑制期内不再执行" 1 "$(lines "$t/out")"
check "日志：触发时间、匹配行、成功，不含命令输出" 'x ERROR [db].failX y | 执行成功' \
    "$(sed -E 's/^\[[0-9-]{10} [0-9:]{8}\] 匹配: //' "$t/log")"
stop
command -v pgrep >/dev/null || fail_msg "缺少 pgrep，无法检查 tail 残留"
check "退出后 tail 不残留" 0 "$(pgrep -f -- "tail -n0 -F .*--pid=.* -- $f" | wc -l)"

# 日志时区：默认 Asia/Shanghai，可用 TZ 覆盖
for tz in '' UTC; do
    TZ=$tz start "$f" 'tz' 1 0
    echo tz >>"$f"; sleep 1
    want=$(TZ=${tz:-Asia/Shanghai} date +%F' '%H)
    check "时区 ${tz:-默认}" "$want" "$(sed -E 's/^\[([0-9-]{10} [0-9]{2}).*/\1/' "$t/log")"
    stop
done

# UTF-8 locale 下 GBK 字节不影响 * 匹配
LANG=en_US.UTF-8 start "$f" 'GBK*fail' 1 0
printf 'GBK \xb4\xed\xce\xf3 fail\n' >>"$f"; sleep 1
check "GBK 内容通配命中" 1 "$(lines "$t/out")"
stop

# HITS=3、SUPPRESS=0：每 3 次命中执行一次
start "$f" 'hit' 3 0
for i in 1 2 3 4 5 6 7; do echo "hit $i" >>"$f"; done
sleep 1
check "HITS=3 命中 7 次执行 2 次" $'hit 3\nhit 6' "$(sort "$t/out" 2>/dev/null)"
stop

# WINDOW=2、HITS=2：窗口过期清零
start "$f" 'win' 2 0 2
echo win1 >>"$f"; sleep 2.5; echo win2 >>"$f"; sleep 0.5; echo win3 >>"$f"; sleep 1
check "窗口过期清零后重新计数" 'win3' "$(cat "$t/out" 2>/dev/null)"
stop

# 执行失败：日志含退出码与完整输出
start "$f" 'bad' 1 0 60 'echo out1; echo err1 >&2; exit 3'
echo bad >>"$f"; sleep 1
check "失败输出完整错误" "bad | 执行失败 rc=3"$'\nout1\nerr1' \
    "$(sed -E 's/^\[[0-9-]{10} [0-9:]{8}\] 匹配: //' "$t/log")"
stop

# 超时：TERM 终止，日志含已有输出；忽略 TERM 时 5 秒后 KILL
TIMEOUT=1 start "$f" 'slow' 1 0 60 'echo part; sleep 10'
echo slow >>"$f"; sleep 2
check "超时终止并记录" "slow | 执行超时 1s rc=124"$'\npart' \
    "$(sed -E 's/^\[[0-9-]{10} [0-9:]{8}\] 匹配: //' "$t/log")"
stop
TIMEOUT=1 start "$f" 'hang' 1 0 60 'trap "" TERM; echo part; sleep 20'
echo hang >>"$f"; sleep 7.5
check "忽略 TERM 时 KILL" "hang | 执行超时 1s rc=137"$'\npart' \
    "$(sed -E 's/^\[[0-9-]{10} [0-9:]{8}\] 匹配: //' "$t/log")"
stop

# SUPPRESS=2：抑制过期后再次执行
start "$f" 'boom' 1 2
echo boom1 >>"$f"; sleep 0.5; echo boom2 >>"$f"; sleep 2.5; echo boom3 >>"$f"; sleep 1
check "抑制过期后再次执行" $'boom1\nboom3' "$(cat "$t/out" 2>/dev/null)"
stop

# 文件已存在（inotify 模式）轮转后继续监控
h=$t/c.log; : >"$h"
start "$h" 'rot' 1 0
echo rot1 >>"$h"; sleep 1
mv "$h" "$h.1"; echo rot2 >"$h"; sleep 2
check "已存在文件轮转后继续监控" $'rot1\nrot2' "$(cat "$t/out" 2>/dev/null)"
stop

# 文件不存在时启动（轮询模式）、轮转（重建）后约 1 秒内切换
g=$t/b.log
start "$g" 'up' 1 0
echo up1 >"$g"; sleep 2
mv "$g" "$g.1"; echo up2 >"$g"; sleep 2
check "文件创建与轮转后继续监控" $'up1\nup2' "$(cat "$t/out" 2>/dev/null)"
stop

if ((failures)); then echo "失败 $failures 项"; exit 1; fi
echo "全部通过"
