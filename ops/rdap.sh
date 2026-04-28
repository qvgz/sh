#!/usr/bin/env bash
# 查询域名信息

set -euo pipefail

path="$(cd -- "$(dirname -- "$0")" && pwd -P)"
default_file="${path}/rdap.sh.txt"
query_interval="${RDAP_QUERY_INTERVAL:-3}"

rdap_apis=(
  "https://rdap.verisign.com/com/v1/domain/"
  "https://rdap.markmonitor.com/rdap/domain/"
)

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
  local domain="$1"
  local suffix
  domain="${domain#http://}"
  domain="${domain#https://}"
  domain="${domain%%/*}"
  domain="${domain%%:*}"
  domain="${domain%.}"
  domain="$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')"

  for suffix in "${second_level_suffixes[@]}"; do
    if [[ "$domain" == *".${suffix}" ]]; then
      awk -F. 'NF >= 3 { print $(NF-2) "." $(NF-1) "." $NF }' <<<"$domain"
      return
    fi
  done

  awk -F. 'NF >= 2 { print $(NF-1) "." $NF }' <<<"$domain"
}

query_rdap() {
  local domain="$1"
  local api body

  for api in "${rdap_apis[@]}"; do
    if body="$(query_rdap_api "$api" "$domain")"; then
      printf '%s\n' "$body"
      return 0
    fi
  done

  return 1
}

query_rdap_api() {
  local api="$1"
  local domain="$2"

  curl -fsSL --connect-timeout 3 --max-time 8 "${api}${domain}" 2>/dev/null
}

query_rdap_with_expiration() {
  local domain="$1"
  local api body date attempt

  for attempt in 1 2 3; do
    for api in "${rdap_apis[@]}"; do
      if body="$(query_rdap_api "$api" "$domain")"; then
        date="$(expiration_date <<<"$body" 2>/dev/null || true)"
        if [[ -n "$date" ]]; then
          printf '%s\n' "$body"
          return 0
        fi
      fi
    done

    [[ "$attempt" != "3" ]] && sleep "$query_interval"
  done

  return 1
}

query_whois() {
  whois "$1"
}

query_whois_with_expiration() {
  local domain="$1"
  local body date attempt

  for attempt in 1 2 3; do
    if body="$(query_whois "$domain" 2>/dev/null)"; then
      date="$(whois_expiration_date <<<"$body")"
      if [[ -n "$date" ]]; then
        printf '%s\n' "$body"
        return 0
      fi
    fi

    [[ "$attempt" != "3" ]] && sleep "$query_interval"
  done

  return 1
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
  date -j -f "%Y-%m-%d" "$date_value" +%s 2>/dev/null
}

days_until() {
  local date_value="$1"
  local today_epoch date_epoch

  today_epoch="$(date_to_epoch "$(date +%Y-%m-%d)")" || return 1
  date_epoch="$(date_to_epoch "$date_value")" || return 1
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

cached_query_expiration_date() {
  local cache_file="$1"
  local domain="$2"
  local cached

  if [[ -n "$cache_file" && -f "$cache_file" ]] && cached="$(awk -F '\t' -v domain="$domain" '
    $1 == domain { print $2; found = 1; exit }
    END { if (!found) exit 1 }
  ' "$cache_file")"; then
    if [[ "$cached" != "X" ]]; then
      printf '%s\n' "$cached"
      return 0
    fi
  fi

  if cached="$(query_expiration_date "$domain")"; then
    [[ -n "$cache_file" ]] && printf '%s\t%s\n' "$domain" "$cached" >>"$cache_file"
    printf '%s\n' "$cached"
    return 0
  fi

  return 1
}

resolve_file_path() {
  local file_path="$1"

  if [[ -f "$file_path" ]]; then
    printf '%s\n' "$file_path"
    return 0
  fi

  if [[ -f "$default_file" ]]; then
    printf '%s\n' "$default_file"
    return 0
  fi

  echo "Error: 文件不存在 ${file_path}，默认文件也不存在 ${default_file}" >&2
  return 1
}

sort_check_rows() {
  local input_file="$1"
  local output_file="$2"
  local tmp

  tmp="$(mktemp "${output_file}.sort.XXXXXX")"
  awk '
    NF < 3 { print "0 0 " $0; next }
    { print "1 " $3 " " $0 }
  ' "$input_file" | sort -k1,1n -k2,2n | cut -d' ' -f3- >"$tmp"
  format_check_rows "$tmp" >"$output_file"
  rm -f "$tmp"
}

format_check_rows() {
  awk '
    {
      domains[NR] = $1
      dates[NR] = $2
      days[NR] = $3
      if (length($1) > domain_width) domain_width = length($1)
      if (length($2) > date_width) date_width = length($2)
    }

    END {
      for (i = 1; i <= NR; i++) {
        if (days[i] == "") {
          printf "%-*s  %s\n", domain_width, domains[i], dates[i]
        } else {
          printf "%-*s  %-*s  %s\n", domain_width, domains[i], date_width, dates[i], days[i]
        }
      }
    }
  ' "$1"
}

write_check_file() {
  local file_path="$1"
  local cache_file="${2:-}"
  local output_file="${file_path}.check.txt"
  local tmp domain query_domain new_date left_days

  tmp="$(mktemp "${output_file}.tmp.XXXXXX")"

  while read -r domain _ || [[ -n "${domain:-}" ]]; do
    [[ -z "${domain:-}" ]] && continue

    query_domain="$(root_domain "$domain")"
    if [[ -z "$query_domain" ]] || ! new_date="$(cached_query_expiration_date "$cache_file" "$query_domain")"; then
      printf '%s X\n' "$domain" >>"$tmp"
      sleep "$query_interval"
      continue
    fi

    if left_days="$(days_until "$new_date")"; then
      printf '%s %s %s\n' "$domain" "$new_date" "$left_days" >>"$tmp"
    else
      printf '%s %s\n' "$domain" "$new_date" >>"$tmp"
    fi

    sleep "$query_interval"
  done <"$file_path"

  sort_check_rows "$tmp" "$output_file"
  rm -f "$tmp"
}

write_due_file() {
  local file_path="$1"
  local days_limit="$2"
  local check_file="${file_path}.check.txt"
  local output_file="${file_path}.check.${days_limit}d.txt"
  local tmp

  tmp="$(mktemp "${output_file}.tmp.XXXXXX")"

  awk -v days_limit="$days_limit" '
    $2 == "X" { print; next }
    NF >= 3 && $3 >= 0 && $3 <= days_limit { print }
  ' "$check_file" >"$tmp"

  sort_check_rows "$tmp" "$output_file"
  rm -f "$tmp"
}

main() {
  local verbose=0
  local file_mode=0
  local due_mode=0
  local file_path="$default_file"
  local due_days=30
  local query_cache=""

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
    query_cache="$(mktemp "${TMPDIR:-/tmp}/rdap-cache.XXXXXX")"
    file_path="$(resolve_file_path "$file_path")"
    write_check_file "$file_path" "$query_cache"
    if [[ "$due_mode" == "1" ]]; then
      write_due_file "$file_path" "$due_days"
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
