#!/usr/bin/env bash
# 网宿 CDN 刷新脚本

username="$WS_USERNAME"
apiKey="$WS_APIKEY"
date=$(env LANG="en_US.UTF-8" date -u "+%a, %d %b %Y %H:%M:%S GMT")
password=$(printf "%s" "$date" | openssl dgst -sha1 -hmac "$apiKey" -binary | openssl enc -base64)

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <[urls=]url1 url2>" >&2
    exit 1
fi

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf "%s" "$value"
}

json_array() {
    local first=1
    local item

    printf "["
    for item in "$@"; do
        if [ "$first" -eq 0 ]; then
            printf ","
        fi
        first=0
        printf '"%s"' "$(json_escape "$item")"
    done
    printf "]"
}

urls=()
dirs=()

args_text="$*"
args_text=${args_text#urls=}

while IFS= read -r item; do
    [ -n "$item" ] || continue
    if [[ "$item" == */ ]]; then
        dirs+=("$item")
    else
        urls+=("$item")
    fi
done < <(printf "%s\n" "$args_text" | tr '[:space:]' '\n')

if [ "${#urls[@]}" -eq 0 ] && [ "${#dirs[@]}" -eq 0 ]; then
    echo "No URL provided" >&2
    exit 1
fi

body="{"
if [ "${#urls[@]}" -gt 0 ]; then
    body+="\"urls\":$(json_array "${urls[@]}"),\"urlAction\":\"delete\""
fi
if [ "${#dirs[@]}" -gt 0 ]; then
    if [ "${#urls[@]}" -gt 0 ]; then
        body+=","
    fi
    body+="\"dirs\":$(json_array "${dirs[@]}"),\"dirAction\":\"expire\""
fi
body+="}"

request() {
    curl -s --url "https://open.chinanetcenter.com/ccm/purge/ItemIdReceiver" \
        -X "POST" \
        -u "$username:$password" \
        -H "Date:$date" \
        -H "Content-Type: application/json" \
        --connect-timeout 10 \
        --max-time 30 \
        -d "$body"
}

response=$(request)
status=$?

if [ "$status" -eq 28 ]; then
    response=$(request)
    status=$?
fi

printf "%s\n" "$response"

if [ "$status" -ne 0 ]; then
    exit "$status"
fi

code=$(printf "%s" "$response" | sed -n 's/.*"Code"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')

if [ "$code" = "1" ]; then
    exit 0
fi

exit 1
