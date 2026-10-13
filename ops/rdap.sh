#!/usr/bin/env bash
# WHOIS/RDAP 查询域名注册信息及到期时间

set -euo pipefail

path="$(cd -- "$(dirname -- "$0")" && pwd -P)"
default_file="${path}/rdap.sh.txt"
query_interval="${RDAP_QUERY_INTERVAL:-3}"


second_level_suffixes=(
  "ac.cn"
  "com.cn"
  "edu.cn"
  "gov.cn"
  "net.cn"
  "org.cn"
)

usage() {
  echo "Usage: $0 [-v] domain" >&2
  echo "       $0 [-f [file_path]] [-d [number]]" >&2
}

root_domain() {
  local domain=$1 suffix
  domain=${domain#http://}; domain=${domain#https://}
  domain=${domain%%/*}; domain=${domain%%:*}; domain=${domain%.}
  domain=$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"$domain")
  [[ ${#domain} -le 253 && $domain == *.* && $domain != *..* &&
     $domain != .* && $domain =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] || return 1
  for suffix in "${second_level_suffixes[@]}"; do
    if [[ $domain == *.$suffix ]]; then
      awk -F. 'NF>=3{print $(NF-2)"."$(NF-1)"."$NF}' <<<"$domain"; return
    fi
  done
  awk -F. '{print $(NF-1)"."$NF}' <<<"$domain"
}

query_rdap() {
  local domain=$1 api body apis expiration
  if [[ ! -s $work/bootstrap.json ]]; then
    curl -fsS --connect-timeout 3 --max-time 10 https://data.iana.org/rdap/dns.json -o "$work/bootstrap.json" || return 1
  fi
  apis=$(jq -er --arg tld "${domain##*.}" '.services[] | select(.[0] | index($tld)) | .[1][]' "$work/bootstrap.json") || return 1
  while IFS= read -r api; do
    [[ $api == https://* ]] || continue
    if body=$(query_rdap_api "$api" "$domain") &&
      jq -e '.objectClassName == "domain" and .errorCode == null' <<<"$body" >/dev/null 2>&1 &&
      expiration=$(expiration_date <<<"$body") &&
      [[ $expiration =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] &&
      TZ=UTC date_to_epoch "$expiration" >/dev/null; then
      printf '%s\n' "$body"; return 0
    fi
  done <<<"$apis"
  return 1
}

query_rdap_api() {
  curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 3 --max-time 8 "${1%/}/domain/$2" 2>/dev/null
}

query_rdap_with_expiration() {
  local body date
  body=$(query_rdap "$1") || return 1
  date=$(expiration_date <<<"$body") || return 1
  [[ -n $date ]] || return 1
  printf '%s\n' "$body"
}

query_whois() {
  command -v whois >/dev/null || return 1
  [[ -n $timeout_bin ]] || return 1
  "$timeout_bin" -k 1 10 whois "$1"
}

query_whois_with_expiration() {
  local body date
  body=$(query_whois "$1" 2>/dev/null) || return 1
  date=$(whois_expiration_date <<<"$body")
  [[ -n $date ]] || return 1
  printf '%s\n' "$body"
}

print_rdap_info() {
  jq -r '
    def event_date($action):
      [
        (.events // [])[]
        | select(.eventAction == $action)
        | (.eventDate // "" | split("T")[0])
        | select(. != "")
      ][0] // empty;

    [
      ["expiration", event_date("expiration")],
      ["last changed", event_date("last changed")],
      ["registration", event_date("registration")],
      ["nameservers", (((.nameservers // [])[0].ldhName) // empty)]
    ][]
    | select(length == 2 and .[1] != "")
    | @tsv
  '
}

print_whois_info() {
  awk -F: '
    BEGIN {
      wanted["Registry Expiry Date"] = "expiration"
      wanted["Expiration Time"] = "expiration"
      wanted["Updated Date"] = "last changed"
      wanted["Creation Date"] = "registration"
      wanted["Registration Time"] = "registration"
      wanted["Name Server"] = "nameservers"
    }

    {
      key = $1
      sub(/^[[:space:]]+/, "", key)
      sub(/[[:space:]]+$/, "", key)
      value = substr($0, length($1) + 2)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if (value ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
        value = substr(value, 1, 10)
      }
    }

    key in wanted && !(key in seen) {
      values[wanted[key]] = value
      seen[key] = 1
    }

    END {
      if ("expiration" in values) print "expiration\t" values["expiration"]
      if ("last changed" in values) print "last changed\t" values["last changed"]
      if ("registration" in values) print "registration\t" values["registration"]
      if ("nameservers" in values) print "nameservers\t" values["nameservers"]
    }
  '
}

print_domain_info() {
  local domain="$1"
  local body parsed date

  if body="$(query_whois_with_expiration "$domain")"; then
    date="$(whois_expiration_date <<<"$body")"
    parsed="$(print_whois_info <<<"$body")"
    if [[ -n "$date" && -n "$parsed" ]]; then
      printf '%s\n' "$parsed"
      return 0
    fi
  fi

  if body="$(query_rdap_with_expiration "$domain")"; then
    parsed="$(print_rdap_info <<<"$body" 2>/dev/null || true)"
    if [[ -n "$parsed" ]]; then
      printf '%s\n' "$parsed"
      return 0
    fi
  fi

  echo "Error: 无法查询 ${domain}，whois 与 RDAP 接口均已失败." >&2
  return 1
}

print_domain() {
  local verbose="$1"
  local input="$2"
  local domain body

  domain="$(root_domain "$input")"
  if [[ -z "$domain" ]]; then
    echo "Error: 无效域名 ${input}" >&2
    return 1
  fi

  if [[ "$verbose" == "1" ]]; then
    if body="$(query_whois_with_expiration "$domain")"; then
      printf '%s\n' "$body"
      return 0
    fi

    body="$(query_rdap "$domain")" || {
      echo "Error: 无法查询 ${domain}，whois 与 RDAP 接口均已失败." >&2
      return 1
    }
    jq . <<<"$body"
  else
    print_domain_info "$domain"
  fi
}

date_to_epoch() {
  local date_value="$1"

  date -d "$date_value" +%s 2>/dev/null && return 0
  date -j -f "%Y-%m-%d %T" "$date_value 00:00:00" +%s 2>/dev/null
}

days_until() {
  local date_value="$1"
  local today_epoch date_epoch

  today_epoch="$(TZ=UTC date_to_epoch "$(date +%Y-%m-%d)")" || return 1
  date_epoch="$(TZ=UTC date_to_epoch "$date_value")" || return 1
  echo $(((date_epoch - today_epoch) / 86400))
}

expiration_date() {
  jq -r '
    [
      (.events // [])[]
      | select(.eventAction == "expiration")
      | (.eventDate // "" | split("T")[0])
      | select(. != "")
    ][0] // empty
  '
}

whois_expiration_date() {
  awk -F: '
    {
      key = $1
      sub(/^[[:space:]]+/, "", key)
      sub(/[[:space:]]+$/, "", key)
      if (key != "Registry Expiry Date" && key != "Expiration Time") next

      value = substr($0, length($1) + 2)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if (value ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
        value = substr(value, 1, 10)
      }
      print value
      exit
    }
  '
}

query_expiration_date() {
  local domain="$1"
  local body date

  if body="$(query_whois_with_expiration "$domain")"; then
    date="$(whois_expiration_date <<<"$body")"
    [[ -n "$date" ]] && printf '%s\n' "$date" && return 0
  fi

  if body="$(query_rdap_with_expiration "$domain")"; then
    date="$(expiration_date <<<"$body" 2>/dev/null || true)"
    [[ -n "$date" ]] && printf '%s\n' "$date" && return 0
  fi

  return 1
}


normalize_domain() { root_domain "$1"; }
lookup_date() { query_expiration_date "$1"; }
check_runtime() {
  local bin
  for bin in curl jq awk; do
    command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; return 1; }
  done
  timeout_bin=$(command -v timeout || command -v gtimeout || true)
}

resolve_file_path() {
  local requested=$1
  [[ -n $requested ]] || requested=$default_file
  [[ -f $requested && -r $requested ]] || { printf '清单不可读：%s\n' "$requested" >&2; return 1; }
  printf '%s\n' "$requested"
}

# 每次运行缓存成功和失败结果；报告用同目录临时文件替换。
write_check_file() {
  local file=$1 output=$1.check.txt domain value days query_domain
  local rows=$work/rows stage
  : >"$rows"
  while read -r domain _ || [[ -n $domain ]]; do
    domain=${domain%$'\r'}
    [[ -n $domain && $domain != \#* ]] || continue
    query_domain=$(normalize_domain "$domain") || {
      printf '%s X\n' "$domain" >>"$rows"; RESULT=1; continue
    }
    if [[ ! -f $work/cache/$query_domain ]]; then
      if value=$(lookup_date "$query_domain") && [[ -n $value ]]; then
        printf '%s\n' "$value" >"$work/cache/$query_domain"
      else
        printf 'X\n' >"$work/cache/$query_domain"
      fi
      sleep "$query_interval"
    fi
    value=$(cat "$work/cache/$query_domain")
    if [[ $value != X ]] && days=$(days_until "$value"); then
      printf '%s %s %s\n' "$domain" "$value" "$days" >>"$rows"
    else
      printf '%s X\n' "$domain" >>"$rows"; RESULT=1
    fi
  done <"$file"
  stage=$(mktemp "${output}.XXXXXX")
  # 保留排序中间文件于 work，失败时不覆盖旧报告。
  awk '{print ($2=="X" ? "0 0 " : "1 " $3 " ") $0}' "$rows" |
    sort -k1,1n -k2,2n | cut -d' ' -f3- >"$work/sorted"
  if format_rows "$work/sorted" >"$stage" && mv -f -- "$stage" "$output"; then :; else
    rm -f -- "$stage"; return 1
  fi
  printf '报告：%s\n' "$output"
}

format_rows() {
  awk '{d[NR]=$1;e[NR]=$2;n[NR]=$3;if(length($1)>w)w=length($1)}
    END{for(i=1;i<=NR;i++)printf "%-*s  %-10s  %s\n",w,d[i],e[i],n[i]}' "$1"
}

main() {
  local verbose=0 file_mode=0 due_mode=0 requested='' due_days=30 file stage
  RESULT=0
  while (( $# )); do
    case "$1" in
      -v) verbose=1; shift ;;
      -f) file_mode=1; shift
          if (( $# )) && [[ $1 != -* ]]; then requested=$1; shift; fi ;;
      -d) due_mode=1; shift
          if (( $# )) && [[ $1 =~ ^[0-9]+$ ]]; then due_days=$1; shift; fi ;;
      -h|--help) usage; return 0 ;;
      -*) usage; return 2 ;;
      *) break ;;
    esac
  done
  [[ $query_interval =~ ^[0-9]+([.][0-9]+)?$ ]] || { printf '查询间隔无效\n' >&2; return 2; }
  [[ $due_days =~ ^(0|[1-9][0-9]*)$ && ${#due_days} -le 6 ]] || return 2
  check_runtime
  work=$(mktemp -d "${TMPDIR:-/tmp}/domain-query.XXXXXX")
  trap 'rm -rf -- "$work"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  mkdir "$work/cache"
  if (( file_mode || due_mode )); then
    (( $# == 0 )) || { usage; return 2; }
    file=$(resolve_file_path "$requested")
    write_check_file "$file"
    if (( due_mode )); then
      stage=$(mktemp "${file}.check.${due_days}d.txt.XXXXXX")
      if awk -v days="$due_days" '$2=="X" || (NF>=3 && $3<=days)' "$file.check.txt" >"$stage" &&
        mv -f -- "$stage" "$file.check.${due_days}d.txt"; then :; else
        rm -f -- "$stage"; return 1
      fi
      printf '到期清单：%s\n' "$file.check.${due_days}d.txt"
    fi
    return "$RESULT"
  fi
  (( $# == 1 )) || { usage; return 2; }
  domain=$(normalize_domain "$1") || { printf '域名无效：%s\n' "$1" >&2; return 2; }
  print_domain "$verbose" "$domain"
}

main "$@"
