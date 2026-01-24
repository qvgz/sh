#!/usr/bin/env bash
# TCP 连接统计
# 1) 远端公网 IPv4 来访连接数（按 RemoteIP=peer 聚合）
# 2) 本机公网 IPv4 发起/维持连接数（按 LocalIP=local 聚合）
# 依赖：iproute2 (ss), awk, sort
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/ip-conn-stat.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/ip-conn-stat.sh)"

set -euo pipefail

for bin in ss awk sort mktemp; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: missing command: $bin" >&2; exit 1; }
done

# 排除非公网/保留地址（按常用范围）
NONPUBLIC_RE='^(10[.]|127[.]|169[.]254[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[0-1])[.]|100[.](6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])[.]|198[.](18|19)[.])'

tmp_in="$(mktemp)"
tmp_out="$(mktemp)"
trap 'rm -f "$tmp_in" "$tmp_out"' EXIT

ss -Hnt state established \
| awk -v re="$NONPUBLIC_RE" -v tin="$tmp_in" -v tout="$tmp_out" '
  function is_public_ipv4(ip) { return (ip !~ re) }
  {
    local_addr=$4
    peer_addr=$5

    # Local IP（本机）
    if (match(local_addr, /^([0-9]+[.][0-9]+[.][0-9]+[.][0-9]+):[0-9]+$/, m1)) {
      lip=m1[1]
      if (is_public_ipv4(lip)) out_cnt[lip]++
    }

    # Peer IP（远端）
    if (match(peer_addr, /^([0-9]+[.][0-9]+[.][0-9]+[.][0-9]+):[0-9]+$/, m2)) {
      rip=m2[1]
      if (is_public_ipv4(rip)) in_cnt[rip]++
    }
  }
  END {
    for (ip in in_cnt)  printf "%d\t%s\n", in_cnt[ip], ip > tin
    for (ip in out_cnt) printf "%d\t%s\n", out_cnt[ip], ip > tout
  }
'

echo "=== 远端公网 IPv4 来访连接数（RemoteIP/peer，ESTAB）==="
sort -nr "$tmp_in" || true
echo
echo "=== 本机公网 IPv4 发起/维持连接数（LocalIP/local，ESTAB）==="
sort -nr "$tmp_out" || true
