#!/bin/bash
# 记录维护 brew 应用列表
# 环境变量 $BREW_LIST_PATH 指定 brew-list 路径，缺省 brew.sh 与同目录
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/macos/brew.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/macos/brew.sh)"

set -euo pipefail

# --- 配置与环境探测 ---

# 动态探测 brew 路径
BREW_BIN=$(command -v brew)
if [[ -z "$BREW_BIN" ]]; then
    # 回退尝试常见路径
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        BREW_BIN="/opt/homebrew/bin/brew"
    elif [[ -x "/usr/local/bin/brew" ]]; then
        BREW_BIN="/usr/local/bin/brew"
    else
        echo "Error: brew not found." >&2
        exit 1
    fi
fi

# 确定清单路径 (优先环境变量 -> 脚本所在目录 -> 用户主目录)
if [[ -n "${BREW_LIST_PATH}" ]]; then
    LIST_FILE="${BREW_LIST_PATH}"
elif [[ -n "${BASH_SOURCE[0]}" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
    # 只有当脚本作为文件执行时，dirname 才有效
    LIST_FILE="$(dirname "${BASH_SOURCE[0]}")/brew-list"
else
    # 管道执行 (curl | bash) 时的兜底路径
    LIST_FILE="${HOME}/.brew-list"
fi

# PIN 清单路径 (防止 grep 报错)
PIN_FILE="${BREW_PIN_LIST_PATH:-${LIST_FILE}.pin}"

# 确保文件存在以免报错
touch "$LIST_FILE"
[[ -f "$PIN_FILE" ]] || touch "$PIN_FILE"

# --- 核心逻辑 ---

cmd="$1"
shift # 移除第一个参数(command)，剩余的都是 args

case "$cmd" in
    install)
        # 1. 执行 brew install
        "$BREW_BIN" install "$@"

        # 2. 成功后记录 (仅记录非 flag 参数)
        for app in "$@"; do
            if [[ "$app" != -* ]]; then
                echo "$app" >> "$LIST_FILE"
            fi
        done

        # 3. 去重排序 (sort -u 替代 临时文件 mv)
        # 使用内存临时文件操作，保证原子性
        tmp=$(mktemp)
        sort -u "$LIST_FILE" > "$tmp" && mv "$tmp" "$LIST_FILE"
    ;;

    uninstall|remove)
        # 1. 执行 brew uninstall
        "$BREW_BIN" uninstall "$@"

        # 2. 成功后从清单移除
        for app in "$@"; do
            if [[ "$app" != -* ]]; then
                # macOS 原生 sed 写法 (-i '')，且使用锚点 ^...$ 精确匹配
                sed -i '' "/^${app}$/d" "$LIST_FILE"
            fi
        done
    ;;

    upgrade)
        # 优化管道逻辑：
        # 1. outdated --greedy 列出所有可更新项
        # 2. grep -v -F -f 排除 PIN 列表中的包 (精确字符串匹配)
        # 3. xargs 传递给 upgrade
        # 注意：如果 pin list 为空，grep -f 可能行为异常，需预处理

        if [[ -s "$PIN_FILE" ]]; then
            "$BREW_BIN" outdated --greedy | awk '{print $1}' | grep -v -F -f "$PIN_FILE" | xargs -r "$BREW_BIN" upgrade
        else
            "$BREW_BIN" outdated --greedy | awk '{print $1}' | xargs -r "$BREW_BIN" upgrade
        fi
    ;;

    *)
        # 透传其他命令
        "$BREW_BIN" "$cmd" "$@"
    ;;
esac
