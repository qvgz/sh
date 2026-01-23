#!/bin/bash
# 获取域名系统实际得到 IP

get_ip_host() {
    local domain="$1"
    host "$domain" | grep "has address" | awk '{print $NF}' | head -n1
}

get_ip_host "$1"
