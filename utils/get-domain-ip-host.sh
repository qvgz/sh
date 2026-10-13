#!/usr/bin/env bash
# 输出本机 DNS 记录

set -o pipefail
domain=${1:-}
if (( $# != 1 )) || [[ -z $domain || $domain == -* || $domain == *[[:space:]/:]* ]]; then
    printf '用法：%s 域名\n' "$0" >&2
    exit 2
fi
command -v host >/dev/null || { printf '缺少命令：host\n' >&2; exit 1; }
answer=$(LC_ALL=C host -W 3 -R 1 "$domain") || exit 1
awk '
$0 !~ / has address / {next}
    {
        ip=$NF
        if (ip !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) next
        split(ip,a,".")
        for (i=1;i<=4;i++) if (a[i]>255) next
        print ip; found=1; exit
    }
    END {if (!found) exit 1}
' <<<"$answer"
