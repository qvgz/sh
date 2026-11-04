#!/usr/bin/env bash
# WHOIS/RDAP 查询域名注册信息及到期时间

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
default_list="$script_dir/rdap.sh.txt"
interval=${RDAP_QUERY_INTERVAL:-3}
bootstrap_url=https://data.iana.org/rdap/dns.json
three_level_suffixes="ac.cn com.cn edu.cn gov.cn net.cn org.cn"
date_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

usage() {
  cat >&2 <<EOF
Usage: $0 [-v] domain
       $0 [-f [file]] [-d [days]]
EOF
}

# 域名、子域名或 HTTP(S) URL -> 小写根域名
root_domain() {
  local d
  d=$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"$1")
  d=${d#http://}; d=${d#https://}
  d=${d%%/*}; d=${d%%:*}; d=${d%.}
  [[ ${#d} -le 253 && $d =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || return 1
  awk -F. -v list=" $three_level_suffixes " '{
    n = (NF >= 3 && index(list, " " $(NF-1) "." $NF " ")) ? 3 : 2
    out = $(NF-n+1); for (i = NF-n+2; i <= NF; i++) out = out "." $i
    print out
  }' <<<"$d"
}

to_epoch() {
  TZ=UTC date -d "$1" +%s 2>/dev/null || TZ=UTC date -j -f '%Y-%m-%d %T' "$1 00:00:00" +%s 2>/dev/null
}

valid_date() { [[ $1 =~ $date_re ]] && to_epoch "$1" >/dev/null; }

days_until() {
  local today target
  today=$(to_epoch "$(date +%F)") && target=$(to_epoch "$1") || return 1
  echo $(((target - today) / 86400))
}

# 标准化字段：每行 "名称<TAB>值"
whois_info() {
  awk '
    BEGIN {
      m["registry expiry date"] = "expiration"; m["expiration time"] = "expiration"
      m["updated date"] = "last changed"
      m["creation date"] = "registration"; m["registration time"] = "registration"
      m["name server"] = "nameservers"
    }
    {
      i = index($0, ":"); if (!i) next
      k = tolower(substr($0, 1, i - 1)); gsub(/^[ \t]+|[ \t\r]+$/, "", k)
      if (!(k in m) || (m[k] in v)) next
      x = substr($0, i + 1); gsub(/^[ \t]+|[ \t\r]+$/, "", x)
      if (x ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) x = substr(x, 1, 10)
      if (x != "") v[m[k]] = x
    }
    END {
      split("expiration,last changed,registration,nameservers", o, ",")
      for (j = 1; j <= 4; j++) if (o[j] in v) printf "%s\t%s\n", o[j], v[o[j]]
    }'
}

rdap_info() {
  jq -r '
    def ev($a): [(.events // [])[] | select(.eventAction == $a)
                 | (.eventDate // "" | split("T")[0]) | select(. != "")][0] // empty;
    select(.objectClassName == "domain" and .errorCode == null)
    | ["expiration", ev("expiration")], ["last changed", ev("last changed")],
      ["registration", ev("registration")],
      ["nameservers", ((.nameservers // [])[0].ldhName // empty)]
    | select(length == 2) | @tsv'
}

field() { awk -F'\t' -v k="$1" '$1 == k && !f { print $2; f = 1 }'; }

query_whois() {
  local body
  command -v whois >/dev/null && command -v timeout >/dev/null || return 1
  body=$(timeout -k 1 10 whois "$1" 2>/dev/null) || return 1
  valid_date "$(whois_info <<<"$body" | field expiration)" || return 1
  printf '%s\n' "$body"
}

query_rdap() {
  local api body
  if [[ ! -s $work/dns.json ]]; then
    curl -fsS --connect-timeout 3 --max-time 10 -o "$work/dns.json.part" "$bootstrap_url" &&
      mv -f -- "$work/dns.json.part" "$work/dns.json" || return 1
  fi
  while IFS= read -r api; do
    body=$(curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 3 --max-time 8 \
      "${api%/}/domain/$1" 2>/dev/null) || continue
    valid_date "$(rdap_info <<<"$body" 2>/dev/null | field expiration)" || continue
    printf '%s\n' "$body"; return 0
  done < <(jq -r --arg t "${1##*.}" \
    '.services[] | select(any(.[0][]; . == $t)) | .[1][] | select(startswith("https://"))' "$work/dns.json")
  return 1
}

# 设置 src(whois|rdap) 与 body；WHOIS 优先
fetch() {
  if body=$(query_whois "$1"); then src=whois; return 0; fi
  if body=$(query_rdap "$1"); then src=rdap; return 0; fi
  return 1
}

info() { if [[ $src == whois ]]; then whois_info <<<"$body"; else rdap_info <<<"$body"; fi; }

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
  local list=$1 due=$2 report=$1.check.txt input domain value days rc=0
  mkdir -p "$work/cache"
  while read -r -u 3 input _ || [[ -n ${input:-} ]]; do
    input=${input%$'\r'}
    [[ -n $input && $input != \#* ]] || continue
    value=X
    if domain=$(root_domain "$input"); then
      if [[ ! -f $work/cache/$domain ]]; then
        if fetch "$domain"; then info | field expiration; else echo X; fi >"$work/cache/$domain"
        sleep "$interval"
      fi
      value=$(<"$work/cache/$domain")
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
  local verbose=0 batch=0 list=$default_list due='' bin domain
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
  [[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "RDAP_QUERY_INTERVAL 无效：$interval" >&2; return 2; }
  for bin in curl jq awk; do
    command -v "$bin" >/dev/null || { echo "缺少命令：$bin" >&2; return 1; }
  done

  work=$(mktemp -d "${TMPDIR:-/tmp}/rdap.XXXXXX")
  trap 'rm -rf -- "$work"' EXIT

  if ((batch)); then
    (($# == 0 && !verbose)) || { usage; return 2; }
    [[ -f $list && -r $list ]] || { echo "清单不可读：$list" >&2; return 2; }
    check_list "$list" "$due"
    return
  fi

  (($# == 1)) || { usage; return 2; }
  domain=$(root_domain "$1") || { echo "域名无效：$1" >&2; return 2; }
  fetch "$domain" || { echo "无法查询 $domain：WHOIS 与 RDAP 均失败" >&2; return 1; }
  if ((!verbose)); then info
  elif [[ $src == whois ]]; then printf '%s\n' "$body"
  else jq . <<<"$body"; fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
