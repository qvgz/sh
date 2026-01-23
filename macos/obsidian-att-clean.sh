#!/bin/bash
# Obsidian 清理 0 链接附件

set -euo pipefail

# 1. 环境与变量准备
if [[ -z "$OBSIDIAN_VAULT_PATH" || -z "$OBSIDIAN_TRASH_PATH" ]]; then
    echo "错误: 环境变量 OBSIDIAN_VAULT_PATH 或 OBSIDIAN_TRASH_PATH 未设置"
    exit 1
fi

VAULT_NAME="${OBSIDIAN_VAULT_PATH##*/}"
ATT_DIR_REL="归档/附件" # 可根据需要改为变量

# 定义临时文件
REF_TEMP=$(mktemp)       # 存储全库 MD 内容
ALL_ATTS_LIST=$(mktemp)  # 存储所有附件的完整路径
ATT_NAMES_LIST=$(mktemp) # 仅存储附件文件名（用于匹配模式）
FOUND_LIST=$(mktemp)     # 存储被引用的文件名

# 注册退出时的清理钩子
trap 'rm -f "$REF_TEMP" "$ALL_ATTS_LIST" "$ATT_NAMES_LIST" "$FOUND_LIST"' EXIT

echo ">>> 正在构建全库文本索引..."
# 2. 构建全库文本索引 (保持原逻辑)
find "$OBSIDIAN_VAULT_PATH" \
    -type d \( -name ".obsidian" -o -name ".trash" -o -path "*/${ATT_DIR_REL}" \) -prune \
    -o -type f -name "*.md" -exec cat {} + | tr -d '\0' > "$REF_TEMP"

echo ">>> 正在扫描附件列表..."
# 3. 获取所有附件路径及文件名
# 这里使用 path 匹配你指定的附件目录
find "$OBSIDIAN_VAULT_PATH" -path "*/${ATT_DIR_REL}/*" -type f > "$ALL_ATTS_LIST"

# 如果没有附件，直接退出
if [[ ! -s "$ALL_ATTS_LIST" ]]; then
    echo "未找到任何附件，脚本结束。"
    exit 0
fi

# 提取纯文件名用于 grep 匹配模式
# sed 's!.*/!!' 等同于 basename，但处理大文件更快
sed 's!.*/!!' "$ALL_ATTS_LIST" > "$ATT_NAMES_LIST"

echo ">>> 正在执行批量比对 (核心加速步骤)..."
# 4. 核心优化：使用 grep -f 批量查找
# -F: 固定字符串 (速度快)
# -o: 只输出匹配的部分 (防止一行多引用时漏掉)
# -f: 从文件中读取匹配模式 (一次性匹配几千个文件名)
# sort -u: 去重，得到“所有被引用的附件名白名单”
if [[ -s "$ATT_NAMES_LIST" ]]; then
    grep -F -o -f "$ATT_NAMES_LIST" "$REF_TEMP" | sort -u > "$FOUND_LIST"
else
    touch "$FOUND_LIST"
fi

echo ">>> 正在处理未引用文件..."
# 5. 集合求差与移动
# 使用 awk 高效筛选：遍历所有附件路径，如果其文件名不在 FOUND_LIST 中，则输出路径
awk '
    # 读取白名单 (FOUND_LIST)，存入数组 a
    NR==FNR { a[$0]=1; next }

    # 读取所有附件路径 (ALL_ATTS_LIST)
    {
        filepath=$0
        # 提取文件名 (逻辑同 basename)
        filename=filepath
        sub(".*/", "", filename)

        # 如果文件名不在数组 a 中，说明未被引用
        if (!(filename in a)) {
            print filepath
        }
    }
' "$FOUND_LIST" "$ALL_ATTS_LIST" | while read -r att_full_path; do

    att_name="${att_full_path##*/}"

    # 忽略系统文件
    if [[ "$att_name" == ".DS_Store" ]]; then continue; fi

    # 计算回收站路径
    rel_path="${att_full_path#"$OBSIDIAN_VAULT_PATH"/}"
    trash_dest_dir="${OBSIDIAN_TRASH_PATH}/${VAULT_NAME}/${rel_path%/*}"

    echo "移动: $att_name -> 回收站"
    mkdir -p "$trash_dest_dir"
    mv "$att_full_path" "${trash_dest_dir}/${att_name}"

done

echo "清理完成。"
