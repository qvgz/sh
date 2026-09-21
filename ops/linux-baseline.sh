#!/usr/bin/env bash
# 采集 CPU、内存、磁盘、网络当前负载
# 功能：依次采集 Linux 当前 CPU、内存、磁盘、网络负载；每类默认采集 25 秒。
#       所有逐秒原始数据按类别写入同一个文本，末尾给出各项峰值。
# 实现：读取 /proc/stat、/proc/meminfo、/proc/diskstats 和 /proc/net/dev，使用
#       相邻快照差值计算速率和利用率；采集过程不会主动制造测试负载。
# 使用：chmod +x linux_baseline.sh
#       ./linux_baseline.sh [--duration 25] [--output current_load.txt]
#       --duration 是每一类的采集秒数，总耗时约为其 4 倍。

set -euo pipefail
export LC_ALL=C

DURATION=25
OUTPUT="linux_load_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
TMP_DIR=""

usage() {
    printf '用法: %s [--duration 秒数] [--output 报告文件]\n' "$0"
}
die() { printf '错误: %s\n' "$*" >&2; exit 1; }

while (($#)); do
    case "$1" in
        --duration) (($# >= 2)) || die "--duration 缺少值"; DURATION=$2; shift 2 ;;
        --output) (($# >= 2)) || die "--output 缺少值"; OUTPUT=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
done

[[ $DURATION =~ ^[1-9][0-9]*$ ]] || die "duration 必须是正整数"
[[ -r /proc/stat && -r /proc/meminfo && -r /proc/diskstats && -r /proc/net/dev ]] ||
    die "本脚本只能在具有 /proc 的 Linux 系统运行"

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/linux-load.XXXXXX") || die "无法创建临时目录"
cleanup() { [[ -n ${TMP_DIR:-} && -d $TMP_DIR ]] && rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$(dirname -- "$OUTPUT")" || die "无法创建输出目录"
: >"$OUTPUT" || die "无法写入: $OUTPUT"

section() { printf '\n===== %s =====\n' "$1" | tee -a "$OUTPUT"; }
progress() { printf '[%s] %s（%ss）\n' "$(date '+%F %T')" "$1" "$DURATION" >&2; }
cpu_snapshot() { awk '/^cpu / {for(i=2;i<=NF;i++) t+=$i; print t, $5+$6}' /proc/stat; }

collect_cpu() {
    local file="$TMP_DIR/cpu" prev idle total current_idle dtotal didle used i
    progress "采集 CPU 当前负载"
    printf 'timestamp cpu_used_pct cpu_idle_pct\n' >"$file"
    read -r prev idle < <(cpu_snapshot)
    for ((i=0; i<DURATION; i++)); do
        sleep 1
        read -r total current_idle < <(cpu_snapshot)
        dtotal=$((total-prev)); didle=$((current_idle-idle))
        used=$(awk -v t="$dtotal" -v id="$didle" 'BEGIN{printf "%.2f",t?100*(t-id)/t:0}')
        printf '%s %s %s\n' "$(date '+%F_%T')" "$used" "$(awk -v u="$used" 'BEGIN{printf "%.2f",100-u}')" >>"$file"
        prev=$total; idle=$current_idle
    done
    section "CPU 原始数据"; cat "$file" >>"$OUTPUT"
}

collect_memory() {
    local file="$TMP_DIR/memory" i total avail swap_total swap_free
    progress "采集内存当前负载"
    printf 'timestamp total_MiB available_MiB used_pct swap_used_MiB swap_used_pct\n' >"$file"
    for ((i=0; i<DURATION; i++)); do
        read -r total avail swap_total swap_free < <(awk '
            /^MemTotal:/ {m=$2} /^MemAvailable:/ {a=$2}
            /^SwapTotal:/ {s=$2} /^SwapFree:/ {f=$2} END{print m,a,s,f}' /proc/meminfo)
        awk -v ts="$(date '+%F_%T')" -v t="$total" -v a="$avail" -v st="$swap_total" -v sf="$swap_free" \
            'BEGIN{printf "%s %.2f %.2f %.2f %.2f %.2f\n",ts,t/1024,a/1024,t?100*(t-a)/t:0,(st-sf)/1024,st?100*(st-sf)/st:0}' >>"$file"
        sleep 1
    done
    section "内存原始数据"; cat "$file" >>"$OUTPUT"
}

disk_snapshot() {
    local dev
    while read -r _ _ dev reads _ read_sectors _ writes _ write_sectors _ _ io_ms _; do
        [[ $dev =~ ^(loop|ram|fd|sr)[0-9] ]] && continue
        [[ -e /sys/class/block/"$dev"/partition ]] && continue
        printf '%s %s %s %s %s %s\n' "$dev" "$reads" "$read_sectors" "$writes" "$write_sectors" "$io_ms"
    done </proc/diskstats
}

collect_disk() {
    local file="$TMP_DIR/disk" before="$TMP_DIR/disk.before" after="$TMP_DIR/disk.after" i
    progress "采集磁盘当前负载"
    printf 'timestamp device read_MiB_s write_MiB_s read_IOPS write_IOPS util_pct\n' >"$file"
    disk_snapshot >"$before"
    for ((i=0; i<DURATION; i++)); do
        sleep 1; disk_snapshot >"$after"
        awk -v ts="$(date '+%F_%T')" 'NR==FNR{r[$1]=$2;rs[$1]=$3;w[$1]=$4;ws[$1]=$5;io[$1]=$6;next}
            ($1 in r){u=($6-io[$1])/10;if(u>100)u=100;if(u<0)u=0;
            printf "%s %s %.2f %.2f %d %d %.2f\n",ts,$1,($3-rs[$1])/2048,($5-ws[$1])/2048,$2-r[$1],$4-w[$1],u}' \
            "$before" "$after" >>"$file"
        mv -- "$after" "$before"
    done
    section "磁盘原始数据"; cat "$file" >>"$OUTPUT"
}

network_snapshot() { awk -F'[: ]+' 'NR>2 {print $2,$3,$11}' /proc/net/dev; }

collect_network() {
    local file="$TMP_DIR/network" before="$TMP_DIR/net.before" after="$TMP_DIR/net.after" i
    progress "采集网络当前负载"
    printf 'timestamp interface rx_MiB_s tx_MiB_s total_MiB_s\n' >"$file"
    network_snapshot >"$before"
    for ((i=0; i<DURATION; i++)); do
        sleep 1; network_snapshot >"$after"
        awk -v ts="$(date '+%F_%T')" 'NR==FNR{rx[$1]=$2;tx[$1]=$3;next}
            ($1 in rx){r=($2-rx[$1])/1048576;t=($3-tx[$1])/1048576;
            printf "%s %s %.3f %.3f %.3f\n",ts,$1,r,t,r+t}' "$before" "$after" >>"$file"
        mv -- "$after" "$before"
    done
    section "网络原始数据"; cat "$file" >>"$OUTPUT"
}

write_summary() {
    section "最高负载汇总"
    {
        awk 'NR>1&&$2+0>m{m=$2+0;l=$0} END{printf "CPU 最高使用率: %.2f%% (%s)\n",m,l}' "$TMP_DIR/cpu"
        awk 'NR>1&&$4+0>m{m=$4+0;l=$0} END{printf "内存最高使用率: %.2f%% (%s)\n",m,l}' "$TMP_DIR/memory"
        awk 'NR>1{v=$3+$4;if(v>mt){mt=v;lt=$0}if($7+0>mu){mu=$7+0;lu=$0}}
            END{printf "磁盘最高吞吐: %.2f MiB/s (%s)\n磁盘最高利用率: %.2f%% (%s)\n",mt,lt,mu,lu}' "$TMP_DIR/disk"
        awk 'NR>1&&$5+0>m{m=$5+0;l=$0} END{printf "网络最高总吞吐: %.3f MiB/s (%s)\n",m,l}' "$TMP_DIR/network"
    } >>"$OUTPUT"
}

printf 'Linux 当前负载采集报告\n主机: %s\n开始时间: %s\n每类采集时长: %s 秒\n' \
    "$(hostname)" "$(date '+%F %T %z')" "$DURATION" >>"$OUTPUT"
collect_cpu
collect_memory
collect_disk
collect_network
write_summary
printf '\n结束时间: %s\n' "$(date '+%F %T %z')" >>"$OUTPUT"
printf '采集完成：%s\n' "$OUTPUT"
