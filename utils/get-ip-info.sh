#!/usr/bin/env bash
# 查询 IPv4 地理信息

set -o pipefail
ip=${1:-}
apis=(
    "https://api.db-ip.com/v2/free"
    "http://ip-api.com/json"
    "https://ipinfo.io"
    "https://ipwho.is"
    "https://ip.guide"
    "https://reallyfreegeoip.org/json"
    "https://api.ipbase.com/v1/json"
)

octet='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
regex="^($octet\.){3}$octet$"
if (( $# != 1 )) || [[ ! $ip =~ $regex ]]; then
    printf '用法：%s IPv4\n' "$0" >&2
    exit 2
fi
case "$ip" in
    10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*)
        printf '不查询私网 IPv4\n' >&2; exit 1 ;;
esac
for bin in curl jq; do
    command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; exit 1; }
done
# 随机打乱接口顺序，每个接口最多尝试一次。
for ((i = ${#apis[@]} - 1; i > 0; i--)); do
    j=$((RANDOM % (i + 1)))
    tmp=${apis[i]}
    apis[i]=${apis[j]}
    apis[j]=$tmp
done

for url in "${apis[@]}"; do
    body=$(curl -fsS --connect-timeout 3 --max-time 5 "$url" 2>/dev/null) || continue
    if jq -e --arg ip "$ip" '
        type == "object" and (.success != false) and (.error == null) and
        ((.ip // .ipAddress) == $ip)
    ' <<<"$body" >/dev/null 2>&1; then
        jq . <<<"$body"
        exit $?
    fi
done
printf '无法获取 %s 的信息\n' "$ip" >&2
exit 1
