#!/usr/bin/env bash
# centos-optimize.sh 容器集成测试：systemd 特权容器内 docker 场景执行两次校验幂等，再切换 k8s 场景
# 用法：bash tests/centos-optimize-test.sh [镜像...]，需 docker
# 共享内核/时钟/swap 的部分打桩：tuned 守护进程、tuned-adm、chronyd 不调时钟（-x）、modprobe、swapon/swapoff、
# 非网络命名空间隔离的 sysctl（fs/vm/conntrack/neigh）
# shellcheck disable=SC2016
set -uo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)/ops/centos-optimize.sh"
images=("$@")
((${#images[@]})) || images=(almalinux:9 almalinux:10)
failures=0

# test_one 镜像 标签 → 容器 ID 写入全局 cid
test_one() {
    docker build -q --build-arg "IMG=$1" -t "$2" - >/dev/null <<'EOF' || return 1
ARG IMG
FROM $IMG
RUN dnf install -y -q systemd openssh-server tuned chrony libselinux-utils firewalld procps-ng && dnf clean all \
 && systemctl enable sshd firewalld && ssh-keygen -A \
 && echo 'OPTIONS="-F 2 -x"' >/etc/sysconfig/chronyd \
 && mkdir -p /etc/systemd/system/tuned.service.d \
 && printf '[Service]\nType=simple\nExecStart=\nExecStart=/usr/bin/sleep infinity\n' >/etc/systemd/system/tuned.service.d/test.conf \
 && printf '%s\n' '#!/bin/sh' '[ "$1" = recommend ] && { echo virtual-guest; exit; }' '[ "$1" = profile ] && echo "$2" >/run/tuned-profile' 'echo "Current active profile: $(cat /run/tuned-profile 2>/dev/null)"' >/usr/local/sbin/tuned-adm \
 && printf '%s\n' '#!/bin/sh' 'exit 0' >/usr/local/sbin/modprobe \
 && cp /usr/local/sbin/modprobe /usr/local/sbin/swapon && cp /usr/local/sbin/modprobe /usr/local/sbin/swapoff \
 && printf '%s\n' '#!/bin/bash' '[[ "$1 $2" == "-q --load" ]] && exec /usr/sbin/sysctl -q --load <(grep -vE "^(fs|vm)[.]|^net[.]netfilter|neigh" "$3")' 'exec /usr/sbin/sysctl "$@"' >/usr/local/sbin/sysctl \
 && chmod +x /usr/local/sbin/* \
 && printf 'SELINUX=enforcing\nSELINUXTYPE=targeted\n' >/etc/selinux/config \
 && printf '/swapfile none swap defaults 0 0\n' >>/etc/fstab
CMD ["/sbin/init"]
EOF
    cid=$(docker run -d --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        -v "$src:/opt/run.sh:ro" "$2") || return 1
    docker exec "$cid" bash -c 'for _ in $(seq 60); do systemctl is-system-running 2>/dev/null | grep -qE "running|degraded" && exit 0; sleep 1; done; exit 1' || return 1
    docker exec "$cid" bash -Eec 'trap "echo \"断言失败: \$BASH_COMMAND\" >&2" ERR
        bash /opt/run.sh 2>/dev/null && exit 1
        bash /opt/run.sh docker k8s 2>/dev/null && exit 1
        bash /opt/run.sh docker >/tmp/run1.log 2>&1
        bash /opt/run.sh docker >/tmp/run2.log 2>&1
        grep -q "command not found" /tmp/run1.log /tmp/run2.log && exit 1
        grep -q "已写入" /tmp/run2.log && exit 1
        [[ $(grep -c "已写入" /tmp/run1.log) == 10 ]]
        sshd -T | grep -qx "gssapiauthentication no"
        sshd -T | grep -qx "usedns no"
        grep -qx "#/swapfile none swap defaults 0 0" /etc/fstab
        grep -qx SELINUX=permissive /etc/selinux/config
        [[ $(systemctl is-enabled firewalld || true) == disabled ]]
        [[ $(timedatectl show -p Timezone --value) == Asia/Shanghai ]]
        [[ $(systemctl show -p DefaultLimitNOFILE --value) == 1048576 ]]
        [[ $(cat /run/tuned-profile) == virtual-guest ]]
        [[ $(sysctl -n net.ipv4.ip_forward) == 1 && $(sysctl -n net.core.somaxconn) == 65535 ]]
        sysctl -n net.ipv4.ip_local_port_range | grep -qxE "32768[[:space:]]+65535"
        [[ $(sysctl -n net.ipv4.conf.all.rp_filter) == 2 && $(sysctl -n net.ipv4.conf.all.send_redirects) == 0 ]]
        b=$(ls -dtr /var/tmp/el-container-cloud-backup.* | head -n1)
        [[ -f $b/etc/selinux/config && -f $b/etc/fstab ]]
        grep -qx /etc/sysctl.d/99-el-docker.conf "$b/created.list"
        systemctl is-active -q sshd chronyd systemd-journald

        bash /opt/run.sh k8s >/tmp/run3.log 2>&1
        [[ ! -e /etc/sysctl.d/99-el-docker.conf && ! -e /etc/modules-load.d/10-el-docker.conf ]]
        grep -qx br_netfilter /etc/modules-load.d/10-el-k8s.conf
        [[ $(sysctl -n net.bridge.bridge-nf-call-iptables) == 1 && $(sysctl -n net.bridge.bridge-nf-call-ip6tables) == 1 ]]
        [[ $(grep -c "已写入" /tmp/run3.log) == 2 ]]
    '
}

for img in "${images[@]}"; do
    printf '== %s\n' "$img"
    tag="centos-optimize-test:${img//[:\/]/-}"
    cid=""
    if test_one "$img" "$tag"; then
        printf 'PASS: %s\n' "$img"
    else
        printf 'FAIL: %s\n' "$img" >&2; failures=$((failures + 1))
        [[ -n $cid ]] && docker exec "$cid" bash -c 'cat /tmp/run*.log' 2>&1 | tail -40 >&2
    fi
    [[ -n $cid ]] && docker rm -f "$cid" >/dev/null
    docker image rm "$tag" >/dev/null 2>&1
done
((failures == 0))
