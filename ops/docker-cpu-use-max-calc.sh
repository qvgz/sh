#!/usr/bin/env bash
# 容器 cpu 指定使用比例
# $1 最大使用比例，缺省 95%
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/docker-cpu-use-max-calc.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/ops/docker-cpu-use-max-calc.sh)"

function cpu_use_max_calc(){
    use_max=$1
    cpu_num=$(grep -c "processor" /proc/cpuinfo)
    cpu_num_use_max=$(awk "BEGIN{print $cpu_num*${use_max:=0.95}}")
    echo $cpu_num_use_max
}

cpu_use_max_calc $1

