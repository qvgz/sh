#!/usr/bin/env bash
# 保留最近 N 个不同镜像
# 每个仓库保留最近 N 个不同镜像（默认 5），删除超额标签及悬空镜像；容器引用的镜像不删。

set -euo pipefail

usage() {
    printf '用法：%s [--dry-run] [保留镜像数，默认 5]\n' "$0" >&2
    exit 2
}

dry_run=0
keep=
for arg in "$@"; do
    case $arg in
    --dry-run) dry_run=1 ;;
    *)
        [[ -z $keep && $arg =~ ^[1-9][0-9]{0,8}$ ]] || usage
        keep=$arg
        ;;
    esac
done
keep=${keep:-5}
command -v docker >/dev/null || {
    printf '缺少命令：docker\n' >&2
    exit 1
}

# 任一查询失败即退出，避免在信息不全时删除。
used=$(docker ps -aq --no-trunc | xargs -r docker container inspect --format '{{.Image}}')
images=$(docker image ls --no-trunc --format '{{.Repository}} {{.Tag}} {{.ID}}')

# 输入已按创建时间倒序；同仓库同 ID 的多个标签只占一个名额。
targets=$(awk -v keep="$keep" -v used="$used" '
    BEGIN {
        n = split(used, ids, "\n")
        for (i = 1; i <= n; i++) in_use[ids[i]]
    }
    $1 == "<none>" || $2 == "<none>" { next }
    {
        key = $1 SUBSEP $3
        if (!(key in rank)) rank[key] = ++count[$1]
        if (rank[key] > keep + 0 && !($3 in in_use)) print $1 ":" $2
    }
' <<<"$images")

if ((dry_run)); then
    [[ -z $targets ]] || awk '{print "将删除镜像：" $0}' <<<"$targets"
    # prune 不清理容器引用的悬空镜像，预览同样排除。
    dangling=$(docker image ls --no-trunc --filter dangling=true --format '{{.ID}}')
    while IFS= read -r id; do
        [[ -n $id && $'\n'$used$'\n' != *$'\n'$id$'\n'* ]] || continue
        printf '将清理悬空镜像：%s\n' "$id"
    done <<<"$dangling"
    exit 0
fi

result=0
while IFS= read -r tag; do
    [[ -n $tag ]] || continue
    printf '删除旧镜像：%s\n' "$tag"
    docker image rm -- "$tag" || result=1
done <<<"$targets"

docker image prune -f || result=1
exit "$result"
