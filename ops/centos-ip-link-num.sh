#!/usr/bin/env bash
# centos ip 连接数 ！仅测试 centos 7

set -e

(
    # 排除内网 10. 等等
    ips=$(ip a | grep -vwE '10\.*|127\.*|172\.*|inet6'  | grep inet | awk '{print $2}' | cut -f1 -d'/')
    result=""

    for ip in $ips;do
        eth=$(ip a | grep $ip | awk '{print $NF}')
        num=$(ss -natp | grep -c $ip)
        result+="$num $eth $ip\n"
    done
    echo -e $result | sort
)

