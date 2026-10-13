#!/usr/bin/env bash
# 按本地/远端地址统计已建立 TCP IPv4 连接

set -euo pipefail
for bin in ss awk sort mktemp; do
    command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; exit 1; }
done
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
: >"$tmp/peer"; : >"$tmp/local"
# 指定 state 后 ss 不输出 State 列，地址在第 3、4 列。
ss -Hnt4 state established | awk -v dir="$tmp" '
    function public(ip, a) {
        if (ip !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) return 0
        split(ip,a,".")
        if (a[1]==0 || a[1]==10 || a[1]==127 || a[1]>=224) return 0
        if (a[1]==100 && a[2]>=64 && a[2]<=127) return 0
        if (a[1]==169 && a[2]==254) return 0
        if (a[1]==172 && a[2]>=16 && a[2]<=31) return 0
        if (a[1]==192 && (a[2]==168 || (a[2]==0 && (a[3]==0 || a[3]==2)))) return 0
        if (a[1]==198 && (a[2]==18 || a[2]==19 || (a[2]==51 && a[3]==100))) return 0
        if (a[1]==203 && a[2]==0 && a[3]==113) return 0
        return 1
    }
    {local_ip=$3; peer_ip=$4; sub(/:[0-9]+$/,"",local_ip); sub(/:[0-9]+$/,"",peer_ip)
     if (public(local_ip)) local_count[local_ip]++
     if (public(peer_ip)) peer_count[peer_ip]++}
    END {
        for (ip in peer_count) print peer_count[ip], ip > (dir "/peer")
        for (ip in local_count) print local_count[ip], ip > (dir "/local")
    }
'
printf '=== 远端公网 IPv4 连接数（peer，ESTABLISHED）===\n'
sort -k1,1nr -k2,2 "$tmp/peer"
printf '\n=== 本机公网 IPv4 连接数（local，ESTABLISHED）===\n'
sort -k1,1nr -k2,2 "$tmp/local"
