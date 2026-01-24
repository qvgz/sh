#!/usr/bin/env bash
# 获取域名系统实际得到 IP（IPv4）

set -euo pipefail

get_ip_host() {
  local domain="${1:-}"

  # 1) 依赖检查
  if ! command -v host >/dev/null 2>&1; then
    echo "Error: 'host' command not found." >&2
    return 1
  fi

  # 2) 参数检查
  if [[ -z "$domain" ]]; then
    echo "Usage: $0 <domain>" >&2
    return 1
  fi

  # 3) 解析并取第一个合法 IPv4
  # 仅匹配形如：<domain> has address <IPv4>
  local ip
  ip="$(
    host "$domain" 2>/dev/null \
      | awk '
          $0 ~ / has address / {
            ip=$NF
            if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
              split(ip,a,".")
              if (a[1]<=255 && a[2]<=255 && a[3]<=255 && a[4]<=255) { print ip; exit }
            }
          }
        '
  )"

  if [[ -n "$ip" ]]; then
    echo "$ip"
    return 0
  else
    return 1
  fi
}

get_ip_host "${1:-}"
