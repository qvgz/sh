#!/usr/bin/env bash
# 创建新脚本
# 必须参数 $1 类别 $2 文件名

sort=$1
file_name=$2
intro=$3

if [[ $sort == "" ]] || [[ $file_name == "" ]];then
    echo "必须参数 $1 类别 $2 文件名"
    exit 1
fi

new_file_path="./${sort}/${file_name}.sh"

if [[ -f $new_file_path ]] ; then
    echo "$new_file_path 已存在"
    exit 1
fi

func_name=""

case $sort in
    "file" | "install" | "macos" | "ops" | "other")
    ;;
    "func" | "sys")
        if [[ $sort == "func" ]] || [[ $sort == "sys" ]];then
            func_name="${func_name//-/_}"
            func_name="function $func_name() {} $func_name \"\$*\""
        fi
    ;;
    *)
        echo "退出 $sort 不存在"
        exit 1 ;;
esac

cat << EOF > $new_file_path
#!/usr/bin/env bash
# $intro
# bash -c "\$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/${sort}/${file_name}.sh)"
# bash -c "\$(curl -fsSL https://proxy.qvgz.org/sh/${sort}/${file_name}.sh)"

set -eux

$func_name
EOF

code $new_file_path
