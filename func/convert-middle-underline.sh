#!/bin/bash
# 转换中划线为下划线

convert_middle_underline() {
    local input="$1"

    # 健壮性检查：若无输入参数，则不执行逻辑
    if [[ -n "$input" ]]; then
        # 执行参数扩展替换：${parameter//pattern/string}
        # // 表示全局替换（所有中划线）
        printf '%s\n' "${input//-/_}"
    fi
}

convert_middle_underline "$1"
