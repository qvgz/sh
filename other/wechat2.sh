#!/usr/bin/env bash
# macOS 微信双开

set -euo pipefail

SRC="/Applications/WeChat.app"
DST="/Applications/WeChat2.app"
BID_OLD="com.tencent.xinWeChat"
BID_NEW="com.tencent.xinWeChat2"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Error: missing $1" >&2; exit 1; }; }

need sudo
need /usr/libexec/PlistBuddy
need codesign
need xattr
need ditto
need open

# 0) 前置校验
[[ -d "$SRC" ]] || { echo "Error: 未找到 $SRC" >&2; exit 1; }
[[ "$DST" == "/Applications/WeChat2.app" ]] || { echo "Error: DST 非预期路径：$DST" >&2; exit 1; }

INFO_PLIST="$DST/Contents/Info.plist"

# 1) 复制 App（破坏性：先删再拷）
sudo rm -rf "$DST"
sudo ditto "$SRC" "$DST"

# 2) 修改 Bundle ID 与名称
[[ -f "$INFO_PLIST" ]] || { echo "Error: 未找到 $INFO_PLIST" >&2; exit 1; }

# CFBundleIdentifier：Set 失败则 Add
sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BID_NEW" "$INFO_PLIST" \
  || sudo /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BID_NEW" "$INFO_PLIST"

sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName WeChat2" "$INFO_PLIST" \
  || sudo /usr/libexec/PlistBuddy -c "Add :CFBundleName string WeChat2" "$INFO_PLIST"

sudo /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName WeChat2" "$INFO_PLIST" \
  || sudo /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string WeChat2" "$INFO_PLIST"

# 3) 清除隔离标记并重签（ad-hoc）
sudo xattr -cr "$DST"
sudo codesign --force --deep --sign - "$DST"

# 4) 准备独立沙盒目录
C0="$HOME/Library/Containers/$BID_OLD"
C1="$HOME/Library/Containers/$BID_NEW"

case "${1:-new}" in
  copy)
    rm -rf "$C1"
    mkdir -p "$(dirname "$C1")"
    # macOS 推荐用 ditto 复制目录树（权限/属性更合理）
    ditto "$C0" "$C1"
    ;;
  new)
    rm -rf "$C1"
    mkdir -p "$C1"
    ;;
  *)
    echo "Usage: $0 [new|copy]" >&2
    exit 2
    ;;
esac

echo "完成。副本路径：$DST"
echo "原容器：$C0"
echo "新容器：$C1"
echo "启动副本：open \"$DST\""
