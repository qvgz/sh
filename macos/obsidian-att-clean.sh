#!/usr/bin/env bash
# Obsidian 清理 0 链接附件

set -euo pipefail

# 1) 环境与变量准备（兼容 set -u）
if [[ -z "${OBSIDIAN_VAULT_PATH:-}" || -z "${OBSIDIAN_TRASH_PATH:-}" ]]; then
  echo "错误: 环境变量 OBSIDIAN_VAULT_PATH 或 OBSIDIAN_TRASH_PATH 未设置" >&2
  exit 1
fi

VAULT_NAME="${OBSIDIAN_VAULT_PATH##*/}"
ATT_DIR_REL="归档/附件" # 如需改目录只改这里

# 2) 临时文件
ALL_ATTS_LIST="$(mktemp)"
ATT_NAMES_LIST="$(mktemp)"
FOUND_LIST="$(mktemp)"
trap 'rm -f "$ALL_ATTS_LIST" "$ATT_NAMES_LIST" "$FOUND_LIST"' EXIT

echo ">>> 正在扫描附件列表..."

# 关键修复：扫描附件时也要排除 .trash/.obsidian，否则会把回收站里的文件再次当成“附件”扫描到
find "$OBSIDIAN_VAULT_PATH" \
  -type d \( -name ".obsidian" -o -name ".trash" \) -prune \
  -o -path "*/${ATT_DIR_REL}/*" -type f -print > "$ALL_ATTS_LIST"

if [[ ! -s "$ALL_ATTS_LIST" ]]; then
  echo "未找到任何附件，脚本结束。"
  exit 0
fi

# 提取纯文件名（匹配模式文件）
sed 's!.*/!!' "$ALL_ATTS_LIST" > "$ATT_NAMES_LIST"

echo ">>> 正在扫描全库引用（批量比对）..."

# 关键修复：不再拼接全库 md 到一个大文件；直接对 md 文件集合 grep（减少一次全量写/读 IO）
# 同时避免 set -e + pipefail 在“无匹配”场景下中断：各段 grep 允许空结果
find "$OBSIDIAN_VAULT_PATH" \
  -type d \( -name ".obsidian" -o -name ".trash" -o -path "*/${ATT_DIR_REL}" \) -prune \
  -o -type f -name "*.md" -print0 \
| {
    xargs -0 -n 2000 env LC_ALL=C grep -nF -f "$ATT_NAMES_LIST" 2>/dev/null || true
  } \
| {
    # 关键修复：不要写 \!，否则会有 “stray \ before !” 警告
    grep -E '(!\[\[|\[\[|!\[[^]]*\]\(|\]\()' || true
  } \
| {
    grep -oF -f "$ATT_NAMES_LIST" || true
  } \
| sort -u > "$FOUND_LIST"

echo ">>> 正在处理未引用文件..."

awk '
  NR==FNR { a[$0]=1; next }
  {
    filepath=$0
    filename=filepath
    sub(".*/", "", filename)
    if (!(filename in a)) print filepath
  }
' "$FOUND_LIST" "$ALL_ATTS_LIST" | while read -r att_full_path; do
  att_name="${att_full_path##*/}"
  [[ "$att_name" == ".DS_Store" ]] && continue

  rel_path="${att_full_path#"$OBSIDIAN_VAULT_PATH"/}"
  trash_dest_dir="${OBSIDIAN_TRASH_PATH}/${VAULT_NAME}/${rel_path%/*}"
  mkdir -p "$trash_dest_dir"

  dest="${trash_dest_dir}/${att_name}"
  if [[ -e "$dest" ]]; then
    dest="${trash_dest_dir}/${att_name}.$(date +%s)"
  fi

  echo "移动: $att_name -> 回收站"
  mv "$att_full_path" "$dest"
done

echo "清理完成。"
