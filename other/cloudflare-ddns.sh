#!/usr/bin/env bash
# Cloudflare DDNS
# 3 个为必须参数：
# $1 域名，例如：fxtaoo.com。
# $2 二级域名，例如 home.fxtaoo.com。
# $3 cf authorization，参考下文 创建 cf authorization。
# 1 个为可选参数：
# $4 ttl 时间，单位分钟，同时为脚本定期执行时间，缺省为 3。
# 日志默认位置，脚本文件同目录下 cloudflare-ddns.log 文件
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/other/cloudflare-ddns.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/other/cloudflare-ddns.sh)"

set -e

cf_domain_nam=$1
cf_ddns_domain_name=$2
cf_authorization=$3
ttl=$4

ttl=${ttl:=3}
ttl=$(( ttl*60 ))
log_path="$(dirname $0)/cloudflare-ddns.log"

# 验证
if ! jq --version &> /dev/null;then
     echo "jq 命令未找到，脚本退出。" >> $log_path
     exit 1
fi

if [[ $cf_domain_nam == "" || $cf_ddns_domain_name == "" || $cf_authorization == "" ]];then
     echo "$1 $2 $3 为必须参数，有未配置，脚本退出。" >> $log_path
     exit 1
fi

# cf_ddns_domain_ip=$(ping -c 1 ${cf_ddns_domain_name} | head -n 1 | awk '{print $3}' | sed 's/[():]//g')
# cf_ddns_domain_ip=$(dig ${cf_ddns_domain_name} @1.0.0.1 | grep -E '^[^;;]*IN*A*' | head -n 1 | awk '{print $5}')
cf_ddns_domain_ip=$(dig +short @1.0.0.1 ${cf_ddns_domain_name} | head -n1)

# 解析要存在
if [[ ! $cf_ddns_domain_ip ]];then
     echo "$cf_ddns_domain_name 二级域名未配置，脚本退出。" >> $log_path
     exit 1
fi

while true;do
     # 检查出口 ip 与解析是否一致
     query_export_ip_api=""
     export_ip=""

     if [[ ! -p /tmp/cloudflare-ddns ]];then
          mkfifo -m 777 /tmp/cloudflare-ddns
     fi

     while [[ ! $export_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]];do
          case $((RANDOM%6+1)) in
               1)
                    query_export_ip_api="https://api.ipify.org"
               ;;
               2)
                    query_export_ip_api="https://ip.3322.net"
               ;;
               3)
                    query_export_ip_api="https://ifconfig.me"
               ;;
               4)
                    query_export_ip_api="http://ip.sb"
               ;;
               5)
                    query_export_ip_api="https://checkip.amazonaws.com"
               ;;
               6)
                    query_export_ip_api="http://whatismyip.akamai.com"
               ;;
          esac
          (
               export_ip=$(curl -s $query_export_ip_api)
               echo "$export_ip" > /tmp/cloudflare-ddns &
          )
          read -r export_ip < /tmp/cloudflare-ddns
     done

     if [[ "$export_ip" != "$cf_ddns_domain_ip" ]];then
          # 验证 cf_authorization
          success=$(curl -sX GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
          -H "Authorization: Bearer ${cf_authorization}" \
          -H "Content-Type:application/json" | jq '.success')

          if [[ $success != "true" ]];then
               echo "Authorization 有误，脚本退出。" >> $log_path
               exit 1
          fi

          zone_identifier=$(curl -sX GET https://api.cloudflare.com/client/v4/zones \
               -H "Authorization: Bearer ${cf_authorization}" \
               -H "Content-Type:application/json" | jq '.result' | jq "map(select(.name==\"$cf_domain_nam\"))" |   jq '.[0].id' | tr -d '"')

          identifier=$(curl -sX GET https://api.cloudflare.com/client/v4/zones/${zone_identifier}/dns_records \
               -H "Authorization: Bearer ${cf_authorization}" \
               -H "Content-Type:application/json" | jq '.result' | jq "map(select(.name==\"$cf_ddns_domain_name\"))" | jq '.[0].id' | tr -d '"')

          result=$(curl -sX PUT https://api.cloudflare.com/client/v4/zones/${zone_identifier}/dns_records/${identifier} \
               -H "Authorization: Bearer ${cf_authorization}" \
               -H "Content-Type:application/json" \
               --data "{
               \"type\": \"A\",
               \"name\": \"${cf_ddns_domain_name}\",
               \"content\": \"${export_ip}\",
               \"proxied\": false,
               \"ttl\": ${ttl}
          }")

          log="$(date '+%Y-%m-%d %H:%M:%S') $(echo $result | jq '.result.name,.result.content,.success' | xargs)"
          echo $log >> $log_path

          success=$(echo $log | awk '{print $5}')
          if [[ $success == "true" ]];then
               cf_ddns_domain_ip=$export_ip
          fi
     fi

     sleep $ttl
done
