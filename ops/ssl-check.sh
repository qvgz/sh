#!/usr/bin/env bash
# 检测 SSL 证书信息

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
  local domain="$1"
  shift

  echo | openssl s_client -servername "$domain" -connect "${domain}:443" 2>/dev/null \
    | openssl x509 -noout "$@" 2>/dev/null
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
  local domain="$1"
  local summary date attempt

  for attempt in 1 2 3; do
    if summary="$(query_cert_summary "$domain")" && date="$(enddate_from_summary "$summary")"; then
      printf '%s\n' "$date"
      return 0
    fi

    [[ "$attempt" != "3" ]] && sleep "$query_interval"
  done

  return 1
}

date_to_epoch() {
  local date_value="$1"

  date -d "$date_value" +%s 2>/dev/null && return 0
  date -j -f "%Y-%m-%d" "$date_value" +%s 2>/dev/null
}

days_until() {
  local date_value="$1"
  local today_epoch date_epoch

  today_epoch="$(TZ="$timezone" date_to_epoch "$(TZ="$timezone" date +%F)")" || return 1
  date_epoch="$(TZ="$timezone" date_to_epoch "$date_value")" || return 1
  echo $(((date_epoch - today_epoch) / 86400))
}

cached_query_enddate() {
  local cache_file="$1"
  local domain="$2"
  local cached

  if [[ -n "$cache_file" && -f "$cache_file" ]] && cached="$(awk -F '\t' -v domain="$domain" '
    $1 == domain { print $2; found = 1; exit }
    END { if (!found) exit 1 }
  ' "$cache_file")"; then
    [[ "$cached" == "X" ]] && return 1
    printf '%s\n' "$cached"
    return 0
  fi

  if cached="$(query_enddate "$domain")"; then
    [[ -n "$cache_file" ]] && printf '%s\t%s\n' "$domain" "$cached" >>"$cache_file"
    printf '%s\n' "$cached"
    return 0
  fi

  [[ -n "$cache_file" ]] && printf '%s\tX\n' "$domain" >>"$cache_file"
  return 1
}

resolve_file_path() {
  local requested="${1:-}"

  if [[ -n "$requested" && -f "$requested" ]]; then
    printf '%s\n' "$requested"
    return 0
  fi

  if [[ -f "$default_file" ]]; then
    printf '%s\n' "$default_file"
    return 0
  fi

  if [[ -n "$requested" ]]; then
    echo "Error: 文件不存在 ${requested}，且默认文件不存在 ${default_file}" >&2
  else
    echo "Error: 默认文件不存在 ${default_file}" >&2
  fi
  return 1
}

sort_check_file() {
  local input_file="$1"
  local output_file="$2"

  awk '
    $2 == "X" { print "0 0 " $0; next }
    { printf "1 %012d %s\n", $3, $0 }
  ' "$input_file" | sort -k1,1n -k2,2n | cut -d' ' -f3- >"$output_file"
}

write_check_file() {
  local file_path="$1"
  local cache_file="$2"
  local output_file="${file_path}.check.txt"
  local tmp domain enddate left_days

  tmp="$(mktemp "${output_file}.tmp.XXXXXX")"

  while read -r domain _ || [[ -n "${domain:-}" ]]; do
    [[ -z "${domain:-}" ]] && continue

    if enddate="$(cached_query_enddate "$cache_file" "$domain")" && left_days="$(days_until "$enddate")"; then
      printf '%s %s %s\n' "$domain" "$enddate" "$left_days" >>"$tmp"
    else
      printf '%s X\n' "$domain" >>"$tmp"
    fi
  done <"$file_path"

  sort_check_file "$tmp" "$output_file"
  rm -f "$tmp"
}

write_due_file() {
  local check_file="$1"
  local days_limit="$2"
  local output_file="${check_file%.txt}.${days_limit}d.txt"
  local tmp domain enddate left_days

  tmp="$(mktemp "${output_file}.tmp.XXXXXX")"

  while read -r domain enddate left_days _ || [[ -n "${domain:-}" ]]; do
    [[ -z "${domain:-}" ]] && continue

    if [[ "$enddate" == "X" ]]; then
      printf '%s X\n' "$domain" >>"$tmp"
    elif [[ "$left_days" =~ ^-?[0-9]+$ ]] && ((left_days <= days_limit)); then
      printf '%s %s %s\n' "$domain" "$enddate" "$left_days" >>"$tmp"
    fi
  done <"$check_file"

  sort_check_file "$tmp" "$output_file"
  rm -f "$tmp"
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

main() {
  local verbose=0
  local file_mode=0
  local due_mode=0
  local file_path=""
  local due_days=30
  local query_cache=""
  local check_file

  while (($# > 0)); do
    case "$1" in
      -v)
        verbose=1
        shift
        ;;
      -f)
        file_mode=1
        shift
        if (($# > 0)) && [[ "$1" != -* ]]; then
          file_path="$1"
          shift
        fi
        ;;
      -d)
        due_mode=1
        shift
        if (($# > 0)) && [[ "$1" =~ ^[0-9]+$ ]]; then
          due_days="$1"
          shift
        fi
        ;;
      -h|--help)
        usage
        return 0
        ;;
      -*)
        usage
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ "$file_mode" == "1" || "$due_mode" == "1" ]]; then
    file_path="$(resolve_file_path "$file_path")" || return 1
    check_file="${file_path}.check.txt"
    query_cache="$(mktemp "${TMPDIR:-/tmp}/ssl-check-cache.XXXXXX")"
    write_check_file "$file_path" "$query_cache"

    if [[ "$due_mode" == "1" ]]; then
      write_due_file "$check_file" "$due_days"
    fi

    rm -f "$query_cache"
    return
  fi

  if (($# != 1)); then
    usage
    return 1
  fi

  print_domain "$verbose" "$1"
}

main "$@"
