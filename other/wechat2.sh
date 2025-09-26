#!/usr/bin/env bash
# macOS 微信双开
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/other/wechat2.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/other/wechat2.sh)"


set -euo pipefail

SRC="/Applications/WeChat.app"
DST="/Applications/WeChat2.app"
BID_OLD="com.tencent.xinWeChat"
BID_NEW="com.tencent.xinWeChat2"

# 1) 复制 App
sudo rm -rf "$DST"
sudo cp -R "$SRC" "$DST"

# 2) 修改 Bundle ID 与名称
sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BID_NEW" "$DST/Contents/Info.plist"
sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName WeChat2" "$DST/Contents/Info.plist" || true
sudo /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName WeChat2" "$DST/Contents/Info.plist" || true

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
    cp -R "$C0" "$C1"
    ;;
  new)
    rm -rf "$C1"
    mkdir -p "$C1"
    ;;
  *)
    echo "Usage: $0 [new|copy]"; exit 2;;
esac

# echo "完成。启动副本：open \"$DST\""
# echo "原容器：$C0"
# echo "新容器：$C1"