#!/usr/bin/env bash
# 判断是否是 root 用户

is_root() {
    # 逻辑拆解：
    # 1. ${EUID}   : Bash/Zsh 内置变量，保存当前有效用户 ID (Root 为 0)
    # 2. :-$(id -u): 兼容性保底。若非 Bash 环境导致 EUID 为空，才调用 id 命令
    # 3. -eq       : 数值比较，比字符串比较 (=) 更严谨
    if ! [[ "${EUID:-$(id -u)}" -eq 0 ]];then
        echo "Error: 当前用户不是 root 用户" >&2
        return 1
    fi
}

is_root
