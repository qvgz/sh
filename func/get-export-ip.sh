#!/usr/bin/env bash
# 获取出口 IP
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/func/get-export-ip.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/func/get-export-ip.sh)"

get_export_ip() {
    # 0) 依赖检查
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: 'curl' command not found." >&2
        return 1
    fi

    # 1) API 资源池（高可用备选）
    local apis=(
        "https://api.ipify.org"
        "https://ip.3322.net"
        "https://ifconfig.me"
        "https://ip.sb"
        "https://checkip.amazonaws.com"
        "http://whatismyip.akamai.com"
    )

    # 2) IPv4 正则
    local octet="(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"
    local ip_regex="^(${octet}\.){3}${octet}$"

    local export_ip=""
    local max_retries=10
    local i api

    # 3) 固定次数尝试
    for ((i=1; i<=max_retries; i++)); do
        api="${apis[$((RANDOM % ${#apis[@]}))]}"
        export_ip="$(curl -sL --connect-timeout 3 --max-time 5 "$api" | tr -d '[:space:]')"

        if [[ "$export_ip" =~ $ip_regex ]]; then
            echo "$export_ip"
            return 0
        fi
    done

    echo "Error: 无法获取出口 IP，已重试 ${max_retries} 次。" >&2
    return 1
}

get_export_ip
