#!/bin/bash
# 生成随机密码
# $1 为指定位数，缺省为 10 位
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/func/create-passwd.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/func/create-passwd.sh)"

create_passwd() {
    # 1. 参数处理：默认值为 10
    local length="${1:-10}"

    # 2. 边界检查：长度不能小于 4
    if (( length < 4 )); then
        echo "Error: Password length must be at least 4." >&2
        return 1
    fi

    # 3. 定义字符集 (已去除易混淆字符: 0, O, 1, l, I)
    local -r digits="23456789"
    local -r lower="abcdefghijkmnpqrstuvwxyz"
    local -r upper="ABCDEFGHJKMNPQRSTUVWXYZ"
    local -r symbols="!@#$%^&*()-+=[]{}|;:,.<>?"
    local -r all_chars="${digits}${lower}${upper}${symbols}"

    local passwd=""

    # 4. 强制满足复杂度：从每类字符中各取 1 个
    passwd+="${digits:$((RANDOM % ${#digits})):1}"
    passwd+="${lower:$((RANDOM % ${#lower})):1}"
    passwd+="${upper:$((RANDOM % ${#upper})):1}"
    passwd+="${symbols:$((RANDOM % ${#symbols})):1}"

    # 5. 填充剩余长度
    local remaining=$((length - 4))
    if (( remaining > 0 )); then
        # 使用 /dev/urandom 获取高质量随机字符，tr -dc 过滤
        local filler
        filler=$(tr -dc "${all_chars}" < /dev/urandom | head -c "${remaining}")
        passwd+="${filler}"
    fi

    # 6. 最终打乱顺序 (Shuffle)
    # fold -w1 将字符串拆行，shuf 打乱行，tr -d 删除换行符重组
    echo "${passwd}" | fold -w1 | shuf | tr -d '\n'
    echo "" # 补全末尾换行符，保持输出美观
}

create_passwd "$1"
