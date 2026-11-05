#!/usr/bin/env bash
# zoxide-fzf-install.sh 容器集成测试：普通用户 + sudo 执行两次，校验安装、bashrc 幂等与交互加载
# 用法：bash tests/zoxide-fzf-install-test.sh [镜像...]，需 docker 与 GitHub 访问
set -uo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)/ops/zoxide-fzf-install.sh"
images=("$@")
(( ${#images[@]} )) || images=(debian:12 debian:13 ubuntu:24.04 almalinux:10 almalinux:9)
failures=0

for img in "${images[@]}"; do
    printf '== %s\n' "$img"
    # shellcheck disable=SC2016
    if docker run --rm -v "$src:/opt/install.sh:ro" "$img" bash -ec '
        if command -v apt-get >/dev/null; then
            apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo >/dev/null
        else
            dnf install -y -q sudo >/dev/null
        fi
        useradd -m -s /bin/bash t
        echo "t ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/t
        sudo -iu t bash /opt/install.sh
        sudo -iu t bash /opt/install.sh | grep -q "无变化"
        [[ $(grep -c "^# >>> zoxide+fzf >>>$" /home/t/.bashrc) == 1 ]]
        [[ $(tail -n1 /home/t/.bashrc) == "# <<< zoxide+fzf <<<" ]]
        sudo -iu t bash -ic "type -t z zi __fzf_history__" 2>/dev/null | grep -c function | grep -qx 3
    '; then
        printf 'PASS: %s\n' "$img"
    else
        printf 'FAIL: %s\n' "$img" >&2; failures=$((failures + 1))
    fi
done
(( failures == 0 ))
