#!/usr/bin/env bash
# 运行脚本所在目录绝对路径

function get_run_sh_dir_path(){
    # dir_path=$(dirname $0)
    # if [[ $dir_path == "." ]] ;then
    #     dir_path=$(pwd)
    # fi
    # echo ${dir_path}

    dirname ${BASH_SOURCE[0]:-$0}
}
get_run_sh_dir_path
