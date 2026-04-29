#!/usr/bin/env bash
# 生成 README.md 并支持自动安装 Git 钩子

set -euo pipefail

proxy="https://qvgz.org/sh/"
github="https://github.com/qvgz/sh/blob/master/"
outfile="README.md"

generate_readme() {
  exclude_suffixes=(".spec")

  cat > "$outfile" <<'EOF'
# cmd

一些 shell 脚本
EOF

  directories=("install" "ops" "cloud" "func" "macos" "other")

  for head_next in "${directories[@]}"; do
    [[ -d "$head_next" ]] || continue

    printf "\n\n## %s\n\n| 文件名 | 介绍 |\n| :- | :- |\n" "$head_next" >> "$outfile"

    # 仅当前目录层级文件；按字典序稳定输出
    find "$head_next" -maxdepth 1 -type f 2>/dev/null \
      | sort \
      | while IFS= read -r filepath; do
          [[ -n "${filepath:-}" ]] || continue

          file_name="${filepath##*/}"
          for suffix in "${exclude_suffixes[@]}"; do
            [[ -n "$suffix" && "$file_name" == *"$suffix" ]] && continue 2
          done

          intro="$(sed -n '2s/^#[[:space:]]*//p' "$filepath" || true)"
          [[ -n "${intro:-}" ]] || intro="-"

          printf '| [%s](%s%s) | [%s](%s%s) |\n' \
            "$file_name" "$github" "$filepath" "$intro" "$proxy" "$filepath" >> "$outfile"
        done
  done

  echo "README.md 已更新。"
}

install_hook() {
  local hook_file=".git/hooks/pre-commit"

  [[ -d ".git" ]] || { echo "错误: 当前目录不是 Git 仓库。" >&2; return 1; }

  # 用绝对路径写入 hook，避免递归/找不到脚本（兼容 macOS 无 realpath --relative-to）
  local script_abs
  script_abs="$(cd -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")"

  cat > "$hook_file" <<EOF
#!/usr/bin/env bash
set -euo pipefail
"$script_abs"
git add README.md
EOF

  chmod +x "$hook_file"
  echo "Git pre-commit 钩子已安装至 $hook_file"
}

if [[ "${1:-}" == "--install" ]]; then
  install_hook
else
  generate_readme
fi
