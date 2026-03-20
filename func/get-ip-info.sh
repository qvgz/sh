#!/usr/bin/env bash
# 获取 IP 信息
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/func/get-ip-info.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/func/get-ip-info.sh)"

get_ip_info() {
  # 依赖检查
  if ! command -v curl >/dev/null 2>&1; then
      echo "Error: 'curl' command not found." >&2
      return 1
  fi

  # IPv4 IP 检查
  local ip=$1
  local octet="(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"
  local ip_regex="^(${octet}\.){3}${octet}$"
  if [[ ! "$ip" =~ $ip_regex ]]; then
    echo "Error: $ip 不是 IPv4 IP"
    return 1
  fi

  # 内网检查
  if [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^192\.168\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
    echo "这个 IP 是内网"
    return 1
  fi

  # API 资源池
  local apis=(
    "http://ip-api.com/json"
    "https://ipwho.is"
  )

  local ip_info=""
  local max_retries=10
  local i api

  # 固定次数尝试
  for ((i=1; i<=max_retries; i++)); do
    api="${apis[$((RANDOM % ${#apis[@]}))]}"
    if ip_info="$(curl -sL --connect-timeout 3 --max-time 5 "$api/$ip")"; then
      if command -v jq >/dev/null 2>&1; then
        echo "${ip_info}" | jq
      else
        echo "${ip_info}"
      fi
      return 0
    fi
  done

  echo "Error: 无法获取 ${ip} 信息，已重试 ${max_retries} 次。" >&2
  return 1
}

get_ip_info "$1"
