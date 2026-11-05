#!/usr/bin/env bash
# HTTPS/SSL/TLS 证书信息及到期时间

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
default_list="$script_dir/ssl-check.sh.txt"
interval=${SSL_CHECK_QUERY_INTERVAL:-1}
tz=Asia/Shanghai

usage() {
  cat >&2 <<EOF
Usage: $0 [-v] domain
       $0 [-f [file]] [-d [days]]
EOF
}

# 去末尾点、转小写并校验主机名
host_name() {
  local d
  d=$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"${1%.}")
  [[ ${#d} -le 253 && $d =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$ ]] || return 1
  printf '%s\n' "$d"
}

# SNI 连接 443，输出叶证书 PEM；先完整接收，避免管道提前关闭触发 SIGPIPE
fetch_cert() {
  local out
  out=$(timeout -k 1 10 openssl s_client -servername "$1" -connect "$1:443" </dev/null 2>/dev/null) || return 1
  openssl x509 <<<"$out" 2>/dev/null
}

# openssl 日期（如 "Jan  1 00:00:00 2027 GMT"）-> 上海时区 YYYY-MM-DD
cert_date() {
  LC_ALL=C TZ=$tz date -d "$1" +%F 2>/dev/null ||
    LC_ALL=C TZ=$tz date -j -f '%b %e %T %Y %Z' "$1" +%F 2>/dev/null
}

to_epoch() {
  TZ=UTC date -d "$1" +%s 2>/dev/null || TZ=UTC date -j -f '%Y-%m-%d %T' "$1 00:00:00" +%s 2>/dev/null
}

days_until() {
  local today target
  today=$(to_epoch "$(TZ=$tz date +%F)") && target=$(to_epoch "$1") || return 1
  echo $(((target - today) / 86400))
}

# issuer、subject、notBefore、notAfter；日期转换失败保留原值
summary() {
  local line k v
  openssl x509 -noout -issuer -subject -dates | while IFS= read -r line; do
    k=${line%%=*}; v=${line#*=}
    if [[ $k == notBefore || $k == notAfter ]] && v=$(cert_date "$v"); then line="$k=$v"; fi
    printf '%s\n' "$line"
  done
}

enddate() {
  local v
  v=$(openssl x509 -noout -enddate) || return 1
  cert_date "${v#notAfter=}"
}

replace_file() {
  local tmp
  tmp=$(mktemp "$1.XXXXXX") || return 1
  if cat >"$tmp" && mv -f -- "$tmp" "$1"; then return 0; fi
  rm -f -- "$tmp"; return 1
}

align() {
  awk '{ a[NR] = $1; b[NR] = $2; c[NR] = $3; if (length($1) > w) w = length($1) }
    END { for (i = 1; i <= NR; i++) { l = sprintf("%-*s  %-10s  %s", w, a[i], b[i], c[i]); sub(/ +$/, "", l); print l } }'
}

check_list() {
  local list=$1 due=$2 report=$1.check.txt input host pem value days rc=0
  mkdir -p "$work/cache"
  while read -r -u 3 input _ || [[ -n ${input:-} ]]; do
    input=${input%$'\r'}
    [[ -n $input && $input != \#* ]] || continue
    value=X
    if host=$(host_name "$input"); then
      if [[ ! -f $work/cache/$host ]]; then
        if pem=$(fetch_cert "$host") && enddate <<<"$pem"; then :; else echo X; fi >"$work/cache/$host"
        sleep "$interval"
      fi
      value=$(<"$work/cache/$host")
    fi
    if [[ $value != X ]] && days=$(days_until "$value"); then
      printf '%s %s %s\n' "$input" "$value" "$days"
    else
      printf '%s X\n' "$input"; rc=1
    fi
  done 3<"$list" >"$work/rows"

  awk '{ print ($2 == "X" ? "0 0" : "1 " $3), $0 }' "$work/rows" |
    sort -s -k1,1n -k2,2n | cut -d' ' -f3- | align | replace_file "$report"
  echo "报告：$report"
  if [[ -n $due ]]; then
    awk -v n="$due" '$2 == "X" || $3 <= n' "$report" | replace_file "$1.check.${due}d.txt"
    echo "到期清单：$1.check.${due}d.txt"
  fi
  return "$rc"
}

main() {
  local verbose=0 batch=0 list=$default_list due='' bin host pem
  while (($#)); do
    case $1 in
      -v) verbose=1; shift ;;
      -f) batch=1; shift
          if (($#)) && [[ $1 != -* ]]; then list=$1; shift; fi ;;
      -d) batch=1; due=30; shift
          if (($#)) && [[ $1 =~ ^[0-9]{1,6}$ ]]; then due=$((10#$1)); shift; fi ;;
      -h|--help) usage; return 0 ;;
      -*) usage; return 2 ;;
      *) break ;;
    esac
  done
  [[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "SSL_CHECK_QUERY_INTERVAL 无效：$interval" >&2; return 2; }
  for bin in openssl timeout awk; do
    command -v "$bin" >/dev/null || { echo "缺少命令：$bin" >&2; return 1; }
  done

  if ((batch)); then
    (($# == 0 && !verbose)) || { usage; return 2; }
    [[ -f $list && -r $list ]] || { echo "清单不可读：$list" >&2; return 2; }
    work=$(mktemp -d "${TMPDIR:-/tmp}/ssl-check.XXXXXX")
    trap 'rm -rf -- "$work"' EXIT
    check_list "$list" "$due"
    return
  fi

  (($# == 1)) || { usage; return 2; }
  host=$(host_name "$1") || { echo "域名无效：$1" >&2; return 2; }
  pem=$(fetch_cert "$host") || { echo "无法获取证书：$host" >&2; return 1; }
  if ((verbose)); then openssl x509 -noout -text <<<"$pem"; else summary <<<"$pem"; fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
