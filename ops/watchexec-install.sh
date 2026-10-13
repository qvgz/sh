#!/usr/bin/env bash
# watchexec 安装
# 安装 Linux x86_64 musl watchexec 到 /usr/local/bin。

set -euo pipefail
if [[ ${1:-} == --help ]]; then
    printf '用法：sudo bash %s [版本号]；省略版本时查询最新 release\n' "$0"; exit 0
fi
(( $# <= 1 )) || exit 2
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { printf '仅支持 Linux x86_64\n' >&2; exit 1; }
[[ $EUID -eq 0 ]] || { printf '请以 root 执行\n' >&2; exit 1; }
for bin in curl tar jq; do
    command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; exit 1; }
done
version=${1:-}
if [[ -z $version ]]; then
    release=$(curl -fsS --connect-timeout 10 --max-time 30 https://api.github.com/repos/watchexec/watchexec/releases/latest)
    version=$(jq -er '.tag_name' <<<"$release")
fi
version=${version#v}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf '版本号无效\n' >&2; exit 2; }
if [[ -x /usr/local/bin/watchexec ]] && [[ $(/usr/local/bin/watchexec --version) == "watchexec $version" ]]; then
    printf '已安装 %s\n' "$version"; exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
url="https://github.com/watchexec/watchexec/releases/download/v$version/watchexec-$version-x86_64-unknown-linux-musl.tar.xz"
curl -fL --connect-timeout 10 --max-time 180 "$url" -o "$tmp/archive.tar.xz"
# 只提取目标二进制到 stdout，不信任归档中的文件路径。
tar -tJf "$tmp/archive.tar.xz" >"$tmp/members"
member=$(awk '/(^|\/)watchexec$/ {print; n++} END{if(n!=1) exit 1}' "$tmp/members")
tar -xJOf "$tmp/archive.tar.xz" -- "$member" >"$tmp/watchexec"
chmod 0755 "$tmp/watchexec"
[[ $("$tmp/watchexec" --version) == "watchexec $version" ]] || { printf '二进制版本校验失败\n' >&2; exit 1; }
install -d /usr/local/bin
if [[ -e /usr/local/bin/watchexec ]]; then
    backup=$(mktemp /usr/local/bin/watchexec.backup.XXXXXX)
    cp -p /usr/local/bin/watchexec "$backup"
    printf '旧版本备份：%s\n' "$backup"
fi
stage=$(mktemp /usr/local/bin/.watchexec.XXXXXX)
trap 'rm -rf -- "$tmp"; rm -f -- "$stage"' EXIT
install -m 0755 "$tmp/watchexec" "$stage"
mv -f -- "$stage" /usr/local/bin/watchexec
/usr/local/bin/watchexec --version
