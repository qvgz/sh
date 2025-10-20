#!/bin/bash
# 进程守护列表
# 守护进程的执行文件（绝对路径）与参数写入脚本文件同目录下 daemon-list 文本
# 在进程所在目录执行文件，例如：setsid nohup process >> nohup.out 2>&1 &
# 每一行为一个进程
# $1 为检查间隔时间，单位秒，缺省为 3
# 不支持配置重定向，默认输出重定 nohup.out
# 参数不支持特殊正则符号
# nohup.out 保留 512M 大小，超过备份后重置，备份只保留 1 份

path="$(cd -- "$(dirname -- "$0")" && pwd -P)"
daemon_list="${path}/daemon-list"
test -r "$daemon_list" || exit 1

sleep_time=$1
log_limit=$((512*1024*1024))
case "$sleep_time" in ''|*[!0-9]*) sleep_time=3;; esac
log="${path}/daemon-list.log"

# 日志重置
function Log_Reset(){
    if test -f $1; then
        size=$(stat -c %s $1 2>/dev/null)
        test "$size" -gt "$log_limit"
        return $?
    else
        return 1
    fi
}


while true; do
    if Log_Reset "$log"; then
        \mv -f "$log" "$log.bak" \
        && echo "$(date +'%Y-%m-%d %H:%M') 清理 $log" >>"$log"
    fi
    # 兼容“文件末行无换行”
    while IFS= read -r process || test -n "$process"; do
        # 空行或注释跳过
        if test -z "$process" || test "${process:0:1}" = "#"; then
            continue
        fi
        if echo "$process" | grep -Eq '[<>[\]()*+?|^$\\]'; then
            echo "$process 跳过！不支持配置重定向或特殊正则符号" >>"$log"
            continue
        fi
        process_path="$(echo "$process" | awk '{print $1}')"
        test -z "$process_path" && continue
        # 打开目录
        cd -- "$(dirname -- "$process_path")" >>"$log" 2>&1 || continue
        process_name="$(basename -- "$process_path")"
        if Log_Reset "nohup.out"; then
            \cp -f nohup.out nohup.out.bak \
            && :> nohup.out \
            && echo "$(date +'%Y-%m-%d %H:%M') 清理 $process_name nohup.out" >>"$log"
        fi
        # 提取参数
        args="$(echo "$process" | awk '{for (i=2;i<=NF;i++) printf $i" "}' | xargs)"
        if test -z "$args"; then
            cmd="./$process_name"
        else
            cmd="./$process_name $args"
        fi
        if ! pgrep -fx -- "$cmd" >/dev/null 2>&1; then
            test -x "$process_name" || chmod +x "$process_name"
            (setsid nohup $cmd >> nohup.out 2>&1 &)
            echo "$(date +'%Y-%m-%d %H:%M') 启动 $process" >>"$log"
        fi
    done < "$daemon_list"

    sleep $sleep_time
done