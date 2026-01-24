#!/usr/bin/env bash
# 创建新脚本标准化工具
# 用法: ./new.sh <category> <filename> [description]

# 1. 变量命名优化：避免使用 'sort' (系统命令关键字)
category=$1
file_name=$2
intro=${3:-"Created by new.sh"} # 设置默认描述，防止为空

# 2. 帮助函数：标准化输出用法
usage() {
    echo "用法: $0 <分类> <文件名> [描述]"
    echo "示例: $0 ops archlinux-rc-local 'ArchLinux rc.local 配置脚本'"
    echo "分类: file, install, macos, ops, other, func"
}

# 3. 参数校验
if [[ -z "$category" ]] || [[ -z "$file_name" ]]; then
    usage
    exit 1
fi

# 4. 路径处理与目录自动创建 (健壮性提升)
target_dir="./${category}"
new_file_path="${target_dir}/${file_name}.sh"

if [[ ! -d "$target_dir" ]]; then
    echo "目录 $target_dir 不存在，正在创建..."
    mkdir -p "$target_dir"
fi

if [[ -f "$new_file_path" ]]; then
    echo "错误: 文件 $new_file_path 已存在"
    exit 1
fi

# 5. 逻辑处理
func_body=""
call_func=""

case $category in
    "file" | "install" | "macos" | "ops" | "other")
        # 普通脚本，无需额外处理
    ;;
    "func")
        # 修复 Bug: 原脚本直接引用空的 $func_name，应引用 $file_name
        # 将文件名中的连字符转换为下划线，以符合函数命名规范
        func_name_valid="${file_name//-/_}"

        # 构建函数体和调用语句
        func_body="function ${func_name_valid}() {
    # TODO: Implement ${func_name_valid}
    echo \"Running ${func_name_valid} ...\"
}"
        call_func="${func_name_valid} \"\$*\""
    ;;
    *)
        echo "错误: 分类 '$category' 不在允许列表中"
        usage
        exit 1
    ;;
esac

# 6. 生成文件 (优化 heredoc 和格式)
cat << EOF > "$new_file_path"
#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 脚本描述: $intro
# 快速执行 (GitHub): bash -c "\$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/${category}/${file_name}.sh)"
# 快速执行 (Self-host): bash -c "\$(curl -fsSL https://qvgz.org/sh/${category}/${file_name}.sh)"
# -----------------------------------------------------------------------------

set -eux

$func_body

$call_func
EOF

# 7. 赋予执行权限
chmod +x "$new_file_path"
echo "已创建并添加执行权限: $new_file_path"

# 8. 打开编辑器 (检查命令是否存在)
if command -v code &> /dev/null; then
    code "$new_file_path"
else
    echo "未找到 'code' 命令，请手动编辑。"
fi
