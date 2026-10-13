#!/usr/bin/env bash
# 回车、y、yes 为同意
# EOF 或其他输入为拒绝。

is_yes() {
    local input
    read -r -p '是否同意 (yes/no) [Y/n]: ' input || return 1
    case "$input" in
        ''|[yY]|[yY][eE][sS]) return 0 ;;
        *) printf '已取消！\n' >&2; return 1 ;;
    esac
}
is_yes
