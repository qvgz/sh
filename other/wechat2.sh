#!/usr/bin/env bash
# macOS 微信多开
# bash -c "$(curl -fsSL https://qvgz.org/sh/other/wechat2.sh)"

set -euo pipefail

SRC="/Applications/WeChat.app"
BID_OLD="com.tencent.xinWeChat"
COUNT="${1:-2}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Error: missing $1" >&2; exit 1; }; }

need sudo
need /usr/libexec/PlistBuddy
need codesign
need xattr
need ditto
need open

# 0) 前置校验
[[ -d "$SRC" ]] || { echo "Error: 未找到 $SRC" >&2; exit 1; }
[[ "$COUNT" =~ ^[0-9]+$ ]] || { echo "Usage: $0 [count>=2]" >&2; exit 2; }
(( COUNT >= 2 )) || { echo "Usage: $0 [count>=2]" >&2; exit 2; }

set_plist_string() {
  local plist="$1"
  local key="$2"
  local value="$3"

  sudo /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" \
    || sudo /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}

for ((n = 2; n <= COUNT; n++)); do
  DST="/Applications/WeChat${n}.app"
  BID_NEW="${BID_OLD}${n}"
  APP_NAME="WeChat${n}"
  DISPLAY_NAME="微信${n}"
  INFO_PLIST="$DST/Contents/Info.plist"
  INFO_PLIST_ZH_HANS="$DST/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
  CONTAINER="$HOME/Library/Containers/$BID_NEW"

  [[ "$DST" == "/Applications/WeChat${n}.app" ]] || { echo "Error: DST 非预期路径：$DST" >&2; exit 1; }

  # 1) 复制 App（破坏性：先删再拷）
  sudo rm -rf "$DST"
  sudo ditto "$SRC" "$DST"

  # 2) 修改 Bundle ID 与名称
  [[ -f "$INFO_PLIST" ]] || { echo "Error: 未找到 $INFO_PLIST" >&2; exit 1; }
  set_plist_string "$INFO_PLIST" "CFBundleIdentifier" "$BID_NEW"
  set_plist_string "$INFO_PLIST" "CFBundleName" "$APP_NAME"
  set_plist_string "$INFO_PLIST" "CFBundleDisplayName" "$APP_NAME"

  if [[ -f "$INFO_PLIST_ZH_HANS" ]]; then
    set_plist_string "$INFO_PLIST_ZH_HANS" "CFBundleName" "$DISPLAY_NAME"
    set_plist_string "$INFO_PLIST_ZH_HANS" "CFBundleDisplayName" "$DISPLAY_NAME"
  fi

  # 3) 清除隔离标记并重签（ad-hoc）
  sudo xattr -cr "$DST"
  sudo codesign --force --deep --sign - "$DST"

  # 4) 准备独立沙盒目录
  mkdir -p "$CONTAINER"

  echo "完成。副本路径：$DST"
  echo "新容器：$CONTAINER"
  echo "启动副本：open \"$DST\""
done
