#!/usr/bin/env bash
# 进程守护
# 守护进程的执行文件（绝对路径）与参数写入脚本文件同目录下 process-list 文本
# 换行分隔多个进程
# $1 为检查间隔时间，单位秒，缺省为 3。
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/other/process-daemon.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/other/process-daemon.sh)"

set -e

path=$(dirname $0)
sleep_time=$1

while true;do
    while IFS=$'\n';read -r process;do
        process_path=$(echo $process | awk '{print $1}')
        process_name=$(basename $process_path)
        num=$(pgrep -c "$process_name")
        if [[ $process != "" ]] && (( num==0 ));then
            (
                cd "$(dirname $process_path)" || exit 1
                # 所有参数
                args=$(echo $process | awk '{ for (i = 2; i <= NF; i++) print $i }')
                if [[ ! -x $process_name ]]; then chmod u+x $process_name; fi
                eval nohup ./$process_name $args &
                echo "$(date +"%Y-%m-%d %H:%M") 启动 ${process}" >> ${path}/process-daemon.log
            )
        fi
    done <${path}/process-list
    sleep ${sleep_time:=3}
done
