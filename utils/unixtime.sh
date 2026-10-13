#!/usr/bin/env bash
# 时间戳相关

format_unix_time() {
    local timestamp="$1"
    local millis=""

    # 13 位输入保留毫秒尾部，输出时追加到格式化结果，避免丢失精度。
    if [[ "$timestamp" =~ ^[0-9]{13}$ ]]; then
        millis=".${timestamp:10:3}"
        timestamp="${timestamp:0:10}"
    fi

    if date -d '@0' +%s >/dev/null 2>&1; then
        date -d "@$timestamp" "+%F %T${millis}"
    else
        date -r "$timestamp" "+%F %T${millis}"
    fi
}

print_current_unix_ms() {
    local current

    # GNU date 直接支持毫秒输出，命中时只需一次 date 调用。
    current="$(date +%s%3N 2>/dev/null)"
    if [[ -n "$current" && "$current" != *N* ]]; then
        echo "$current"
        return
    fi

    # BSD date 不支持 %N，退化为秒后拼接 000，保持脚本可用。
    echo "$(date +%s)000"
}

if (( $# > 1 )) || { (( $# == 1 )) && [[ $1 != -m && ! $1 =~ ^-?[0-9]+$ ]]; }; then
    printf '用法：%s [-m | 秒时间戳 | 13位毫秒时间戳]\n' "$0" >&2
    exit 2
fi

if [[ $# -eq 0 ]]; then
    date +%s
    exit 0
fi

if [[ "$1" == "-m" ]]; then
    print_current_unix_ms
    exit 0
fi

format_unix_time "$1"
