#!/usr/bin/env bash
# 获取运行脚本所在目录绝对路径

get_real_script_path() {
    local source="${BASH_SOURCE[0]:-$0}"
    local dir

    # 解析所有软链接
    while [[ -L "$source" ]]; do
        dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
        source="$(readlink "$source")"
        [[ "$source" != /* ]] && source="$dir/$source"
    done

    dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
    echo "$dir"
}

get_real_script_path
