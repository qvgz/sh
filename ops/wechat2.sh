#!/usr/bin/env bash
# macOS 微信多开
# macOS 微信副本：独立 Bundle ID，已有目标拒绝覆盖。

set -euo pipefail
count=${1:-2}
if (( $# > 1 )) || [[ ! $count =~ ^[1-9][0-9]?$ ]] || (( count < 2 )); then
    printf '用法：%s [总实例数 2..99，默认 2]\n' "$0" >&2; exit 2
fi
[[ $(uname -s) == Darwin ]] || { printf '仅支持 macOS\n' >&2; exit 1; }
source_app=/Applications/WeChat.app
plist=$source_app/Contents/Info.plist
[[ -f $plist ]] || { printf '未找到微信应用\n' >&2; exit 1; }
for bin in sudo ditto codesign xattr /usr/libexec/PlistBuddy; do
    command -v "$bin" >/dev/null || { printf '缺少命令：%s\n' "$bin" >&2; exit 1; }
done
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
for (( n=2; n<=count; n++ )); do
    target=/Applications/WeChat$n.app
    [[ ! -e $target && ! -L $target ]] || { printf '目标已存在，请先自行备份或移走：%s\n' "$target" >&2; exit 1; }
done
sudo -v
stage=$(sudo mktemp -d /Applications/.wechat-copy.XXXXXX)
trap 'sudo rm -rf -- "$stage"' EXIT
set_value() {
    sudo /usr/libexec/PlistBuddy -c "Set :$2 $3" "$1" ||
        sudo /usr/libexec/PlistBuddy -c "Add :$2 string $3" "$1"
}
for (( n=2; n<=count; n++ )); do
    app=$stage/WeChat$n.app
    target=/Applications/WeChat$n.app
    sudo ditto "$source_app" "$app"
    set_value "$app/Contents/Info.plist" CFBundleIdentifier "$bundle_id$n"
    set_value "$app/Contents/Info.plist" CFBundleName "WeChat$n"
    set_value "$app/Contents/Info.plist" CFBundleDisplayName "微信$n"
    localized=$app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings
    if [[ -f $localized ]]; then
        set_value "$localized" CFBundleName "微信$n"
        set_value "$localized" CFBundleDisplayName "微信$n"
    fi
    sudo xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
    sudo codesign --force --deep --sign - "$app"
    sudo codesign --verify --deep "$app"
    sudo mv -n -- "$app" "$target"
    [[ ! -e $app ]] || { printf '目标出现冲突：%s\n' "$target" >&2; exit 1; }
    printf '已生成：%s\n' "$target"
done
