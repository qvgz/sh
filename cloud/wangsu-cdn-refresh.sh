#!/usr/bin/env bash
# 网宿 CDN 刷新
# 一次提交，不自动重试结果不明的请求

set -eo pipefail
if (( $# == 0 )); then
    printf '用法：WS_USERNAME=... WS_APIKEY=... bash %s [urls=]URL ...\n' "$0" >&2
    exit 2
fi
[[ -n ${WS_USERNAME:-} && -n ${WS_APIKEY:-} ]] || { printf '缺少 WS_USERNAME 或 WS_APIKEY\n' >&2; exit 2; }
for bin in curl openssl jq; do
    command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; exit 1; }
done
urls=(); dirs=()
# 兼容一段空白分隔的 urls= 参数；URL 内空格应预先编码。
for arg in "$@"; do
    arg=${arg#urls=}
    while IFS= read -r item; do
        [[ -n $item ]] || continue
        [[ $item =~ ^https?://[^[:space:]]+$ ]] || { printf 'URL 无效：%s\n' "$item" >&2; exit 2; }
        if [[ $item == */ ]]; then dirs+=("$item"); else urls+=("$item"); fi
    done < <(printf '%s\n' "$arg" | tr '[:space:]' '\n')
done
(( ${#urls[@]} + ${#dirs[@]} )) || { printf 'URL 不能为空\n' >&2; exit 2; }
url_json=$(jq -cn --args '$ARGS.positional' "${urls[@]}")
dir_json=$(jq -cn --args '$ARGS.positional' "${dirs[@]}")
body=$(jq -cn --argjson urls "$url_json" --argjson dirs "$dir_json" '
    {} + (if ($urls|length)>0 then {urls:$urls,urlAction:"delete"} else {} end)
       + (if ($dirs|length)>0 then {dirs:$dirs,dirAction:"expire"} else {} end)')
request_date=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')
password=$(printf '%s' "$request_date" | openssl dgst -sha1 -hmac "$WS_APIKEY" -binary | openssl base64 -A)
# 认证放入受限临时配置，避免 curl 命令行暴露用户名和签名。
umask 077
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
credentials=${WS_USERNAME}:$password
credentials=${credentials//\\/\\\\}
credentials=${credentials//\"/\\\"}
[[ $credentials != *$'\n'* && $credentials != *$'\r'* ]] || exit 2
printf 'user = "%s"\n' "$credentials" >"$tmp/auth"
if response=$(curl -fsS --config "$tmp/auth" --connect-timeout 10 --max-time 30 \
    --url https://open.chinanetcenter.com/ccm/purge/ItemIdReceiver \
    -H "Date: $request_date" -H 'Content-Type: application/json' --data-binary "$body"); then
    printf '%s\n' "$response"
    jq -e '.Code == 1' <<<"$response" >/dev/null
else
    status=$?
    printf '提交失败（curl=%s），结果可能不明；先核实网宿刷新记录再决定是否重试。\n' "$status" >&2
    exit "$status"
fi
