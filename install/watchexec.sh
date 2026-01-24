#!/usr/bin/env bash
# 安装 watchexec
# https://github.com/watchexec/watchexec/
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/watchexec.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/install/watchexec.sh)"

set -euo pipefail

# 0) sudo/root 兼容
SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || { echo "Error: 非 root 执行但系统无 sudo" >&2; exit 1; }
  SUDO="sudo"
fi

# 1) 依赖检查（最小集合）
for bin in curl tar awk sed grep; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: 缺少命令: $bin" >&2; exit 1; }
done

# 2) 架构检测（保持你的范围：x86_64 musl）
arch=""
case "$(uname -m)" in
  x86_64) arch="x86_64-unknown-linux-musl" ;;
  *) echo "Error: 不支持的架构: $(uname -m)（仅支持 x86_64）" >&2; exit 1 ;;
esac

# 3) 获取最新 tag
latest_tag="$(
  curl -fsSL "https://api.github.com/repos/watchexec/watchexec/releases/latest" \
    | grep '"tag_name":' \
    | sed -E 's/.*"([^"]+)".*/\1/'
)"

latest_ver="${latest_tag#v}"
[[ -n "$latest_ver" ]] || { echo "Error: 无法获取最新版本信息（GitHub API 失败/限流？）" >&2; exit 1; }

# 4) 获取本地版本
_ver="0"
if command -v watchexec >/dev/null 2>&1; then
  _ver="$(watchexec --version | awk '{print $2}' || echo 0)"
fi

# 5) 安装/更新
if [[ "$_ver" != "$latest_ver" ]]; then
  echo "发现新版本: ${latest_ver} (当前: ${_ver})，正在安装..."

  download_url="https://github.com/watchexec/watchexec/releases/download/${latest_tag}/watchexec-${latest_ver}-${arch}.tar.xz"

  tmp="$($SUDO mktemp)"
  # 原子写入：下载->解压提取->写 tmp -> chmod -> mv 覆盖
  curl -fL --progress-bar "$download_url" \
    | tar -xJ -O --wildcards "*/watchexec" > "$tmp"

  $SUDO chmod +x "$tmp"
  $SUDO mv -f "$tmp" /usr/bin/watchexec

  echo "安装完成: $(watchexec --version)"
else
  echo "已是最新版本 (${_ver})，无需更新。"
fi
