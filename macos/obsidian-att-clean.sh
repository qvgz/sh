#!/bin/bash
# Obsidian 清理 0 链接附件
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/macos/obsidian-att-clean.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/macos/obsidian-att-clean.sh)"

# 环境变量中 仓库路径 与 0 链接附件暂存路径 不为空
[[ -z $OBSIDIAN_VAULT_PATH || -z $OBSIDIAN_TRASH_PATH ]] && exit 1
# 附件默认存放路径为指定的附件文件夹 "归档/附件"
vault_name="${OBSIDIAN_VAULT_PATH##*/}"
md_path_str=$(find "$OBSIDIAN_VAULT_PATH" -not -path '*/.trash/*' -not -path '*/归档/附件/*' -type f -name '*.md' | awk '{printf("%s%c",$0,10)}')

# md 中含有附件名提前退出
function md_check_att (){
    att_path=$1  
    att_name=$(echo $att_path | awk -F/ '{printf("%s",$NF)}')
    num="$(grep -cr "$att_name" --exclude-dir={.obsidian,.trash,附件,} --include="*.md" "$OBSIDIAN_VAULT_PATH" | awk -F: '{sum+=$2} END {print sum}')"
    if [[ "$num" == "0" ]];then
        # 拼接 0 链接附件暂存路径
        # $OBSIDIAN_TRASH_PATH/vault_name/归档/附件/
        path="$(echo "$att_path" | awk -F${vault_name} '{print $2}')"
        path="${OBSIDIAN_TRASH_PATH}/${vault_name}${path%/*}"
        mkdir -p "$path" && mv "${att_path}" "${path}/${att_name}" 
    fi
}

export vault_name
export md_path_str
export OBSIDIAN_TRASH_PATH
export -f md_check_att

find "$OBSIDIAN_VAULT_PATH" -path '*/归档/附件/*' -type f \
| parallel --no-notice 'md_check_att {}'
