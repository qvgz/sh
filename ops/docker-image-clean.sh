#!/bin/bash
# Docker 镜像清理
# $1 为保留版本数量（缺省保留最近 3 个，按 CREATED 时间由近到远依次）
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/docker-image-clean.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/docker-image-clean.sh)"

set -euo pipefail

# 1. 参数校验
KEEP_NUM=${1:-3}
if [[ ! "$KEEP_NUM" =~ ^[0-9]+$ ]] || [ "$KEEP_NUM" -lt 1 ]; then
    echo "错误: 请输入有效的保留数量 (正整数，建议 >= 3)"
    exit 1
fi

echo "正在清理 <none> 悬空镜像..."
docker image prune -f

# 2. 获取所有非悬空镜像的 Repository (排除 <none>)
REPOS=$(docker images --format "{{.Repository}}" | sort -u)

echo "开始按保留数 $KEEP_NUM 清理旧镜像..."

for repo in $REPOS; do
    # 获取特定仓库的所有镜像 ID，按创建时间从新到旧排序
    # tail -n +$((KEEP_NUM + 1)) 表示从第 N+1 行开始输出（即需要删除的部分）
    IDS=$(docker images --format "{{.CreatedAt}}\t{{.ID}}" "$repo" | \
           sort -r | \
           awk '{print $NF}' | \
           tail -n +$((KEEP_NUM + 1)))

    if [ -n "$IDS" ]; then
        echo "清理 [$repo]:"
        # 逐个删除，避免因某个镜像被占用导致整批失败
        for id in $IDS; do
            echo "  -> 删除旧镜像: $id"
            docker rmi "$id" || true
        done
    fi
done
