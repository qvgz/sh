#!/usr/bin/env bash
# HTTPS/SSL/TLS 证书信息及到期时间

set -euo pipefail

path="$(cd -- "$(dirname -- "$0")" && pwd -P)"
default_file="${path}/ssl-check.sh.txt"
query_interval="${SSL_CHECK_QUERY_INTERVAL:-1}"
timezone="Asia/Shanghai"

usage() {
  echo "Usage: $0 [-v] domain" >&2
  echo "       $0 [-f [file_path]] [-d [number]]" >&2
}

query_cert() {
  local domain=$1 certificate
  shift
  # 先完整接收输出，避免 x509 读完叶证书退出后使 s_client 收到 SIGPIPE。
  certificate=$("$timeout_bin" -k 1 10 openssl s_client -servername "$domain" -connect "$domain:443" </dev/null 2>/dev/null) || return 1
  openssl x509 -noout "$@" <<<"$certificate" 2>/dev/null
}

query_cert_text() {
  local domain="$1"

  query_cert "$domain" -text
}

query_cert_summary() {
  local domain="$1"

  query_cert "$domain" -issuer -subject -dates
}

format_cert_date() {
  local date_value="$1"

  LC_ALL=C TZ="$timezone" date -d "$date_value" +%F 2>/dev/null && return 0
  LC_ALL=C TZ="$timezone" date -j -f "%b %e %T %Y %Z" "$date_value" +%F 2>/dev/null
}

format_summary_dates() {
  local line key value formatted

  while IFS= read -r line; do
    case "$line" in
      notBefore=*|notAfter=*)
        key="${line%%=*}"
        value="${line#*=}"
        if formatted="$(format_cert_date "$value")"; then
          printf '%s=%s\n' "$key" "$formatted"
        else
          printf '%s\n' "$line"
        fi
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done
}

enddate_from_summary() {
  local summary="$1"
  local raw

  raw="$(awk -F= '$1 == "notAfter" { print substr($0, length($1) + 2); exit }' <<<"$summary")"
  [[ -n "$raw" ]] || return 1
  format_cert_date "$raw"
}

query_enddate() {
  local summary
  summary=$(query_cert_summary "$1") || return 1
  enddate_from_summary "$summary"
}

date_to_epoch() {
  local date_value="$1"

  date -d "$date_value" +%s 2>/dev/null && return 0
  date -j -f "%Y-%m-%d %T" "$date_value 00:00:00" +%s 2>/dev/null
}

days_until() {
  local date_value="$1"
  local today_epoch date_epoch

  today_epoch="$(TZ=UTC date_to_epoch "$(TZ="$timezone" date +%F)")" || return 1
  date_epoch="$(TZ=UTC date_to_epoch "$date_value")" || return 1
  echo $(((date_epoch - today_epoch) / 86400))
}

print_domain() {
  local verbose="$1"
  local domain="$2"

  if [[ "$verbose" == "1" ]]; then
    query_cert_text "$domain"
  else
    query_cert_summary "$domain" | format_summary_dates
  fi
}

normalize_domain() {
  local domain=${1%.}
  [[ ${#domain} -le 253 && $domain != -* && $domain != .* && $domain != *..* &&
     $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || return 1
  printf '%s\n' "$domain"
}
lookup_date() { query_enddate "$1"; }
check_runtime() {
  command -v openssl >/dev/null || { printf '缺少命令：openssl\n' >&2; return 1; }
  timeout_bin=$(command -v timeout || command -v gtimeout || true)
  [[ -n $timeout_bin ]] || { printf '需要 timeout 或 gtimeout（coreutils）\n' >&2; return 1; }
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
