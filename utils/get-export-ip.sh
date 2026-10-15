#!/usr/bin/env bash
# 获取出口公网 IPv4 地址

apis=(
  "https://api.ipify.org"
  "https://ip.3322.net"
  "https://ifconfig.me"
  "https://ip.sb"
  "https://checkip.amazonaws.com"
  "https://whatismyip.akamai.com"
)

command -v curl >/dev/null || { printf '缺少命令：curl\n' >&2; exit 1; }
# 随机打乱接口顺序，每个接口最多尝试一次。
for ((i = ${#apis[@]} - 1; i > 0; i--)); do
    j=$((RANDOM % (i + 1)))
    tmp=${apis[i]}
    apis[i]=${apis[j]}
    apis[j]=$tmp
done

octet='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
regex="^($octet\.){3}$octet$"
for api in "${apis[@]}"; do
    ip=$(curl -4 -fsS --connect-timeout 3 --max-time 5 "$api" 2>/dev/null) || continue
    ip=${ip//$'\r'/}
    [[ $ip =~ $regex ]] || continue
    printf '%s\n' "$ip"
    exit 0
done
printf '所有出口 IPv4 查询接口均失败\n' >&2
exit 1
