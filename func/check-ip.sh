#!/usr/bin/env bash
# 检查 IP 格式

function check_ip() {
    IP=$1
    if [[ "$IP" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then
        echo 0
    else
        echo 1
    fi
}
check_ip $1
