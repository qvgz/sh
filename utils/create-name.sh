#!/usr/bin/env bash
# 生成随机用户名

export LC_ALL=C
length=${1:-7}
if (( $# > 1 )) || [[ ! $length =~ ^[1-9][0-9]*$ || ${#length} -gt 6 ]] || (( length < 1 )); then
    printf '用法：%s [长度，1..999999，默认 7]\n' "$0" >&2
    exit 2
fi
# head 取够后会使 tr 收到 SIGPIPE；用实际字节数判断随机源是否成功。
while :; do
    value=$(tr -dc '23456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ' </dev/urandom | head -c "$length")
    [[ ${#value} -eq $length ]] || { printf '读取随机源失败\n' >&2; exit 1; }
    printf '%s' "$value"
    break
done
