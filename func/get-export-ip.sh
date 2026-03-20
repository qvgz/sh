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
    local api idx
    local available_apis=("${apis[@]}")
    local failed_apis=()

    # 3) 随机尝试可用接口，失败接口移出资源池
    while ((${#available_apis[@]} > 0)); do
        idx=$((RANDOM % ${#available_apis[@]}))
        api="${available_apis[$idx]}"
        export_ip="$(curl -sL --connect-timeout 3 --max-time 5 "$api" | tr -d '[:space:]')"

        if [[ "$export_ip" =~ $ip_regex ]]; then
            echo "$export_ip"
            return 0
        fi

        failed_apis+=("$api")
        unset 'available_apis[idx]'
        available_apis=("${available_apis[@]}")
    done

    echo "Error: 无法获取出口 IP，全部接口均已失败 (${#failed_apis[@]} 个)." >&2
    return 1
}

get_export_ip
