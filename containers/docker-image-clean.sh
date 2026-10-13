#!/usr/bin/env bash
# 保留最近 N 个不同镜像
# 默认保留 5 个不同镜像，删除旧标签及悬空镜像。

set -euo pipefail

keep=5

if (( $# > 1 )) || [[ ! $keep =~ ^[1-9][0-9]*$ || ${#keep} -gt 9 ]]; then
    printf '用法：%s [保留镜像数，默认 3]\n' "$0" >&2; exit 2
fi
command -v docker >/dev/null || { printf '缺少命令：docker\n' >&2; exit 1; }
# Docker 默认按创建时间倒序；同一 ID 的多个标签只占一个名额。
images=$(docker image ls --no-trunc --format '{{.Repository}} {{.Tag}} {{.ID}}')
targets=$(awk -v keep="$keep" '
    $1 == "<none>" || $2 == "<none>" {next}
    {key=$1 SUBSEP $3; if (!(key in seen)) {seen[key]=++count[$1]}
     if (seen[key]>keep) print $1 ":" $2}
' <<<"$images")
result=0
while IFS= read -r tag; do
    [[ -n $tag ]] || continue
    printf '删除旧标签：%s\n' "$tag"
    docker image rm -- "$tag" || result=1
done <<<"$targets"
docker image prune -f || result=1
exit "$result"
