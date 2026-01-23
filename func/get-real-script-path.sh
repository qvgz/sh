#!/bin/bash
# 获取运行脚本所在目录绝对路径

get_real_script_path() {
    local source="${BASH_SOURCE[0]:-$0}"
    local dir

    # 循环解析软链接，直到找到最终文件
    while [[ -L "$source" ]]; do
        dir=$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)
        source=$(readlink "$source")
        # 如果 readlink 返回相对路径，需要拼上当前目录
        [[ $source != /* ]] && source="$dir/$source"
    done

    # 获取最终文件的目录
    dir=$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)
    echo "$dir"
}

get_real_script_path
