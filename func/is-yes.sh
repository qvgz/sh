#!/usr/bin/env bash
# 判断是否同意
# 同意标准：回车 y yes (大小写不限)，其他输入为 no

is_yes() {
    read -r -p "是否同意 (yes/no) [Y/n]: " input

    # 使用 [] 字符集匹配大小写，无需转换变量
    # [yY]       匹配 y 或 Y
    # [yY][eE][sS] 匹配 yes, Yes, YES, yEs 等所有组合
    # ""         匹配直接回车
    case "$input" in
        [yY]|[yY][eE][sS]|"")
            return 0
            ;;
        *)
            echo "已取消！" >&2
            return 1
            ;;
    esac
}

is_yes
