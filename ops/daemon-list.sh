#!/bin/bash
# 进程守护列表
# 守护进程的执行文件（绝对路径）与参数写入脚本文件同目录下 daemon-list 文本
# 换行分隔多个进程
# $1 为检查间隔时间，单位秒，缺省为 3。
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/other/daemon-list.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/other/daemon-list.sh)"


path=$(dirname $0)
[[ $path == "." ]] && path="$(pwd)"

daemon_list="${path}/daemon-list"
test -r "$daemon_list" || exit 1

sleep_time=$1
log="${path}/daemon-list.log"

while true;do
    while IFS=$'\n';read -r process;do
        process_path="$(echo $process | awk '{print $1}')"
        process_name="$(basename $process_path)"
        args="$(echo "$process" | awk '{for (i=2;i<=NF;i++){if($i~/^&?>/) break; printf $i" "}}' | xargs)"
        if ! pgrep -f -- "^./${process_name} ${args}\$" > /dev/null; then
            cd "$(dirname $process_path)" &>> "$log" || continue
            test -x "$process_name" || chmod +x "$process_name"
            eval "setsid nohup ./$process_name $args &"
            echo "$(date +"%Y-%m-%d %H:%M") 启动 ${process}" >> "$log" 
        fi
    done < "$daemon_list"
    sleep ${sleep_time:=3}
done
