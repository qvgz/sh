#!/usr/bin/env bash
# 获取域名公网 DNS 解析 IP (IPv4)

get_domain_ip_dig() {
    local domain="$1"
    local dns_server="1.0.0.1"

    # 1) 依赖检查
    if ! command -v dig >/dev/null 2>&1; then
        echo "Error: 'dig' command not found." >&2
        return 1
    fi

    # 2) 参数校验
    if [[ -z "$domain" ]]; then
        echo "Usage: $0 <domain>" >&2
        return 1
    fi

    # 3) 执行查询
    # A        : 查询 IPv4 A 记录
    # +short   : 仅输出结果
    # +time=2  : 单次查询超时 2 秒
    # +tries=1 : 仅尝试 1 次（保证整体超时可预期）
    local ip
    ip="$(dig "@${dns_server}" "${domain}" A +short +time=2 +tries=1 \
        | awk '
            /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
              split($0,a,".")
              if (a[1]<=255 && a[2]<=255 && a[3]<=255 && a[4]<=255) { print; exit }
            }
        ')"

    # 4) 结果验证
    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    else
        return 1
    fi
}

get_domain_ip_dig "$1"
