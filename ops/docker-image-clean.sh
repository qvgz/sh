#!/usr/bin/env bash
# Docker 镜像清理
# $1 为保留版本数量（缺省保留最近 3 个，按 CREATED 时间由近到远依次）
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/docker-image-clean.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/docker-image-clean.sh)"

set -euo pipefail

# 0) 依赖检查
command -v docker >/dev/null 2>&1 || { echo "错误: 未找到 docker 命令" >&2; exit 1; }

# 1) 参数校验
KEEP_NUM="${1:-3}"
if [[ ! "$KEEP_NUM" =~ ^[0-9]+$ ]] || [[ "$KEEP_NUM" -lt 1 ]]; then
  echo "错误: 请输入有效的保留数量 (正整数，建议 >= 3)" >&2
  exit 1
fi

echo "正在清理 <none> 悬空镜像..."
docker image prune -f

# 2) 获取所有非悬空镜像的 Repository（排除 <none>）
REPOS="$(
  docker images --format "{{.Repository}}" \
  | awk '$0 != "<none>"' \
  | sort -u
)"

echo "开始按保留数 $KEEP_NUM 清理旧镜像..."

# 3) 逐 repo 清理（按创建时间从新到旧）
while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue

  # CreatedAt 通常：YYYY-MM-DD HH:MM:SS +0800 CST
  # 这里取前两段作为可稳定排序的 key：$1 $2（日期+时间）
  IDS="$(
    docker images "$repo" --format "{{.CreatedAt}}\t{{.ID}}" \
    | awk '{print $1" "$2"\t"$NF}' \
    | sort -r \
    | awk -F'\t' '{print $2}' \
    | tail -n +"$((KEEP_NUM + 1))"
  )"

  if [[ -n "$IDS" ]]; then
    echo "清理 [$repo]:"
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      echo "  -> 删除旧镜像: $id"
      docker rmi "$id" || true
    done <<< "$IDS"
  fi
done <<< "$REPOS"
