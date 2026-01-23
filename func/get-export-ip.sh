#!/bin/bash
# 获取出口 IP
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/func/get-export-ip.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/func/get-export-ip.sh)"

get_export_ip() {
    # 1. 定义 API 资源池（高可用备选）
    local apis=(
        "https://api.ipify.org"
        "https://ip.3322.net"
        "https://ifconfig.me"
        "https://ip.sb"
        "https://checkip.amazonaws.com"
        "http://whatismyip.akamai.com"
    )

    local export_ip=""
    local max_retries=10
    local count=0

    # 2. 循环探测直到获取合法 IP 或达到最大尝试次数
    # 正则逻辑：匹配标准的 IPv4 格式
    local octet="(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"
    local ip_regex="^(${octet}\.){3}${octet}$"

    while [[ ! "$export_ip" =~ $ip_regex ]]; do
        # 随机选择一个 API
        local api="${apis[$((RANDOM % ${#apis[@]}))]}"

        # 执行请求：
        # -s: 静默模式
        # -L: 跟随重定向
        # --connect-timeout 3: 3秒连接超时，防止脚本挂起
        export_ip=$(curl -sL --connect-timeout 3 "$api" | tr -d '[:space:]')

        ((count++))
        if (( count >= max_retries )); then
            echo "Error: 无法获取出口 IP，已重试 $max_retries 次。" >&2
            return 1
        fi
    done

    echo "$export_ip"
}

get_export_ip
