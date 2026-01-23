#!/bin/bash
# 获取域名公网 DNS 解析 IP

get-domain-ip-dig() {
    local domain="$1"
    local dns_server="1.0.0.1"

    # 1. 依赖检查
    if ! command -v dig &> /dev/null; then
        echo "Error: 'dig' command not found." >&2
        return 1
    fi

    # 2. 参数校验
    if [[ -z "$domain" ]]; then
        echo "Usage: get_domain_ip <domain>" >&2
        return 1
    fi

    # 3. 执行查询
    # A       : 显式指定查询 IPv4 地址 (防止返回 CNAME)
    # +short  : 仅输出结果
    # +time=2 : 设置超时时间为 2秒
    local ip
    ip=$(dig "@${dns_server}" "${domain}" A +short +time=2 | grep -E '^[0-9.]+$' | head -n1)

    # 4. 结果验证 (防止空结果)
    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    else
        return 1
    fi
}

get-domain-ip-dig "$1"
