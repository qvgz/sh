#!/bin/bash
# CentOS 公网 IP 连接数统计
# 依赖：iproute2 (ip, ss)

set -euo pipefail

# 定义私有 IP 正则标准 (RFC 1918) + 环回地址
# 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8
PRIVATE_IP_REGEX='(^127\.)|(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.)'

echo "Count Interface IP"
echo "------------------------"

# 1. ip -o -4: 仅输出 IPv4 单行格式，避免多行解析困难
# 2. awk 过滤掉私有 IP 和 lo 接口，直接提取 [接口名] [IP]
ip -o -4 addr show scope global | awk '{print $2, $4}' | cut -d/ -f1 | \
while read -r iface ip; do
    # 二次过滤：排除匹配私有 IP 正则的地址
    if [[ "$ip" =~ $PRIVATE_IP_REGEX ]]; then
        continue
    fi

    # 3. 使用 ss 过滤源 IP (src)，比 grep 更快更准
    # -n: 不解析域名 (提速关键)
    # -t: 仅 TCP (根据原脚本意图，如需 UDP 加 -u)
    # src: 内核级过滤，无需 grep
    count=$(ss -nt src "$ip" | grep -c "ESTAB")
    # count=$(ss -nt src "$ip" | tail -n +2 | wc -l)

    echo -e "${count}\t${iface}\t${ip}"
done | sort -nr
