#!/bin/bash
# 生成 README.md 并支持自动安装 Git 钩子

proxy="https://qvgz.org/sh/"
github="https://github.com/qvgz/sh/blob/master/"
outfile="README.md"

# --- 核心生成逻辑 ---
generate_readme() {
    # 初始化文件头
    cat > "$outfile" <<EOF
# cmd

一些 shell 脚本
EOF

    # 定义目标目录及其显示顺序
    directories=("install" "ops" "func" "macos" "other")

    for head_next in "${directories[@]}"; do
        # 检查目录是否存在，不存在则跳过
        [[ ! -d "$head_next" ]] && continue

        # 写入二级标题和表格头
        printf "\n\n## %s\n\n| 文件名 | 介绍 |\n| :- | :- |\n" "$head_next" >> "$outfile"

        # 在当前目录下执行 find 并进行内部排序
        # 使用 -maxdepth 1 确保只处理当前层级（如需递归可移除）
        find "$head_next" -type f 2>/dev/null | sort | while read -r filepath; do
            file_name="${filepath##*/}"

            # 提取简介（读取文件第 2 行并剔除开头的 # 号）
            intro=$(sed -n '2s/^#[[:space:]]*//p' "$filepath")
            [[ -z "$intro" ]] && intro="-"

            # 根据目录类型生成行内容
            if [[ "$head_next" == "conf" ]]; then
                echo "| [$file_name]($github$filepath) | [$file_name]($proxy$filepath) |" >> "$outfile"
            else
                echo "| [$file_name]($github$filepath) | [$intro]($proxy$filepath) |" >> "$outfile"
            fi
        done
    done

    echo "README.md 已更新。"
}

# --- 钩子安装逻辑 ---
install_hook() {
    hook_file=".git/hooks/pre-commit"

    if [ ! -d ".git" ]; then
        echo "错误: 当前目录不是 Git 仓库。"
        return 1
    fi

    cat > "$hook_file" <<EOF
#!/bin/bash
# 自动生成的 Git 钩子
./\$(basename "\$0")
git add README.md
EOF

    chmod +x "$hook_file"
    echo "Git pre-commit 钩子已安装至 $hook_file"
}

# --- 执行判断 ---
# 如果执行时带了参数 --install，则安装钩子
if [[ "$1" == "--install" ]]; then
    install_hook
else
    generate_readme
fi
