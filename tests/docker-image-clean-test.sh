#!/usr/bin/env bash
# docker-image-clean.sh 集成测试：在隔离的 dind 内真实删除，不触碰宿主镜像
# 用法：bash tests/docker-image-clean-test.sh [dind 镜像，默认 docker:29-dind]，需 docker 特权容器
set -uo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)/containers/docker-image-clean.sh"
image=${1:-docker:29-dind}

cid=$(docker run -d --privileged -e DOCKER_TLS_CERTDIR= -v "$src:/opt/run.sh:ro" "$image") || exit 1
trap 'docker rm -fv "$cid" >/dev/null' EXIT
docker exec "$cid" sh -c 'for _ in $(seq 60); do docker info >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1' || exit 1
docker exec "$cid" apk add -q bash || exit 1

docker exec -i "$cid" bash -s <<'EOF'
failures=0
check() {
    if [[ $3 == "$2" ]]; then echo "ok   $1"; else
        printf 'FAIL %s\n  期望：%s\n  实际：%s\n' "$1" "$2" "$3"; failures=$((failures + 1)); fi
}
# 创建时间精度按秒，间隔 1 秒保证顺序；无参数生成悬空镜像。
mk() {
    sleep 1
    echo "$RANDOM $*" >/tmp/f
    tar -C /tmp -c f | docker import - "$@" >/dev/null
}
tags() { docker image ls -a --format '{{.Repository}}:{{.Tag}}' | sort | xargs; }
run() { bash /opt/run.sh "$@" >/dev/null 2>&1; echo $?; }

mk app:0
mk app:1
mk app:2; docker tag app:2 app:2b
mk app:3; docker tag app:3 app:3b; docker create --name holder app:3 /f >/dev/null
mk app:4; docker tag app:4 app:4b
mk app:5
mk other:1
mk

all="<none>:<none> app:0 app:1 app:2 app:2b app:3 app:3b app:4 app:4b app:5 other:1"
check "初始镜像" "$all" "$(tags)"
check "两个参数返回 2" 2 "$(run 1 2)"
check "0 返回 2" 2 "$(run 0)"
check "非数字返回 2" 2 "$(run abc)"
check "超长数字返回 2" 2 "$(run 1234567890)"
check "参数错误不删除" "$all" "$(tags)"

check "多余参数返回 2" 2 "$(run --dry-run 1 2)"
check "未知选项返回 2" 2 "$(run --force)"

d=$(docker image ls --no-trunc --filter dangling=true --format '{{.ID}}')
check "dry-run 输出" "将删除镜像：app:0 将清理悬空镜像：$d" "$(bash /opt/run.sh --dry-run | xargs)"
check "dry-run 参数顺序无关" "$(bash /opt/run.sh --dry-run 2)" "$(bash /opt/run.sh 2 --dry-run)"
check "dry-run 返回 0" 0 "$(run --dry-run 2)"
check "dry-run 不删除" "$all" "$(tags)"

check "默认执行返回 0" 0 "$(run)"
check "默认保留 5 个并清理悬空" "app:1 app:2 app:2b app:3 app:3b app:4 app:4b app:5 other:1" "$(tags)"

# 删除失败：继续删除其余标签并执行 prune，最终返回非零。
mkdir /tmp/fake
cat >/tmp/fake/docker <<'FAKE'
#!/bin/sh
[ "$1 $2 $4" = "image rm app:2b" ] && exit 1
exec /usr/local/bin/docker "$@"
FAKE
chmod +x /tmp/fake/docker
mk
rc=$(PATH=/tmp/fake:$PATH run 2)
check "删除失败返回 1" 1 "$rc"
check "删除失败不中断且容器引用保留" "app:2b app:3 app:3b app:4 app:4b app:5 other:1" "$(tags)"

# 查询失败：不做任何删除。
cat >/tmp/fake/docker <<'FAKE'
#!/bin/sh
[ "$1" = ps ] && exit 1
exec /usr/local/bin/docker "$@"
FAKE
rc=$(PATH=/tmp/fake:$PATH run 2)
check "查询容器失败返回非零" 1 "$rc"
check "查询容器失败不删除" "app:2b app:3 app:3b app:4 app:4b app:5 other:1" "$(tags)"

check "参数生效返回 0" 0 "$(run 2)"
check "保留 2 个，容器引用不删" "app:3 app:3b app:4 app:4b app:5 other:1" "$(tags)"
check "重复执行返回 0" 0 "$(run 2)"
check "重复执行无变化" "app:3 app:3b app:4 app:4b app:5 other:1" "$(tags)"

docker rm holder >/dev/null
check "容器移除后返回 0" 0 "$(run 2)"
check "容器移除后可删除" "app:4 app:4b app:5 other:1" "$(tags)"

# 悬空镜像被容器引用：dry-run 预览与 prune 实际结果一致。
mk dang:1
docker create --name holder2 dang:1 /f >/dev/null
held=$(docker container inspect --format '{{.Image}}' holder2)
mk dang:1
mk
free=$(docker image ls --no-trunc --filter dangling=true --format '{{.ID}}' | grep -vxF "$held")
check "dry-run 排除容器引用的悬空镜像" "将清理悬空镜像：$free" "$(bash /opt/run.sh --dry-run 2 | xargs)"
run 2 >/dev/null
check "prune 保留容器引用的悬空镜像" "$held" "$(docker image ls --no-trunc --filter dangling=true --format '{{.ID}}')"

((failures == 0)) && echo "全部通过" || { echo "失败 $failures 项"; exit 1; }
EOF
