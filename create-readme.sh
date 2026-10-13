#!/usr/bin/env bash
# 生成 README.md：按目录列出脚本用途与可选说明文档，排除 configs、tests。

set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export LC_ALL=C

proxy="https://qvgz.org/sh/"
outfile="README.md"
readme_header=$(cat <<'HEADER'
# Shell 脚本

- [cloud/](cloud/)：第三方云平台相关
- [configs/](configs/)：配置模板
- [configs/](configs/)：容器相关
- [ops/](ops/)：功能脚本一般不复用
- [utils/](utils/)：简短功能脚本能复用
- [tests/](tests/)：测试

首行注释简短描述脚本关键功能，作为脚本的简要说明。仅在需要时补充同名 `.sh.md`，记录参数、依赖、关键副作用和功能需求，行为修改时同步更新。脚本的测试脚本统一放在 tests 目录。

脚本使用 Bash，平台和依赖以脚本及说明为准。运行前查看用途；安装、刷新、清理等脚本会修改目标环境。
HEADER
)

# glob 按目录、文件名排序；只收录各顶层目录中的 .sh 文件。
shopt -s nullglob
{
  printf '%s\n' "$readme_header"
  for directory in */; do
    directory=${directory%/}
    case "$directory" in
      configs|tests) continue ;;
    esac

    scripts=("$directory"/*.sh)
    ((${#scripts[@]})) || continue
    printf '\n## %s\n\n| 脚本名 | 介绍 |\n| :- | :- |\n' "$directory"
    for filepath in "${scripts[@]}"; do
      [[ -f "$filepath" ]] || continue
      intro=$(sed -n '2{s/^[[:space:]#]*//;s/[[:space:]]*$//;p;}' "$filepath")
      intro=${intro:--}
      # 防止用途中的竖线拆开 Markdown 表格单元格。
      intro=${intro//|/\\|}
      if [[ -f "$filepath.md" ]]; then
        intro="[$intro]($filepath.md)"
      fi
      printf '| [%s](%s%s) | %s |\n' \
        "${filepath##*/}" "$proxy" "$filepath" "$intro"
    done
  done
} > "$outfile"
