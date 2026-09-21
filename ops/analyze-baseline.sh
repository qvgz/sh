#!/usr/bin/env bash
# 分析 CPU、内存、磁盘和网络性能
# 功能：主动测试 Linux 服务器 CPU、内存、磁盘和网络性能；各轮原始结果按
#       类别写入同一个文本，最后输出适合容量规划的保守稳定性能值。
# 实现：CPU/内存使用 sysbench，磁盘使用 fio，网络使用 iperf3。默认测试
#       5 轮；吞吐/IOPS 取第 25 百分位，延迟/重传取第 75 百分位，不取峰值。
#       这会排除偶发的最好成绩，同时避免一次异常抖动直接代表服务器能力。
# 使用：在另一台机器执行 `iperf3 -s`，然后在被测机执行：
#       chmod +x analyze_baseline.sh
#       ./analyze_baseline.sh --iperf-server 192.0.2.10 --disk-dir /data/test
#       可选：--trials 5 --time 15 --disk-size 1G --output performance.txt
# 注意：本脚本会制造高负载；不要直接在繁忙生产服务器上运行。

set -euo pipefail
export LC_ALL=C

TRIALS=5; TEST_TIME=15; DISK_SIZE=1G; DISK_DIR=/tmp
IPERF_SERVER=""; IPERF_PORT=5201
OUTPUT="linux_performance_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
TMP_DIR=""; TEST_FILE=""

usage() {
    cat <<EOF
用法: $0 --iperf-server 主机 [选项]
  --iperf-server HOST  iperf3 服务端（必需）
  --iperf-port PORT    iperf3 端口（默认 5201）
  --disk-dir DIR       fio 临时文件目录（默认 /tmp）
  --disk-size SIZE     fio 文件大小（默认 1G，建议大于内存缓存）
  --trials N           测试轮数（默认 5，至少 3）
  --time N             每轮子测试秒数（默认 15）
  --output FILE        单一报告文件
EOF
}
die() { printf '错误: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "缺少依赖命令 '$1'"; }

while (($#)); do
    case "$1" in
        --iperf-server) (($#>=2))||die "$1 缺少值"; IPERF_SERVER=$2; shift 2 ;;
        --iperf-port) (($#>=2))||die "$1 缺少值"; IPERF_PORT=$2; shift 2 ;;
        --disk-dir) (($#>=2))||die "$1 缺少值"; DISK_DIR=$2; shift 2 ;;
        --disk-size) (($#>=2))||die "$1 缺少值"; DISK_SIZE=$2; shift 2 ;;
        --trials) (($#>=2))||die "$1 缺少值"; TRIALS=$2; shift 2 ;;
        --time) (($#>=2))||die "$1 缺少值"; TEST_TIME=$2; shift 2 ;;
        --output) (($#>=2))||die "$1 缺少值"; OUTPUT=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
done

[[ -n $IPERF_SERVER ]] || die "必须用 --iperf-server 指定另一台 iperf3 服务器"
[[ $TRIALS =~ ^[0-9]+$ && $TRIALS -ge 3 ]] || die "trials 必须是至少 3 的整数"
[[ $TEST_TIME =~ ^[1-9][0-9]*$ ]] || die "time 必须是正整数"
[[ $IPERF_PORT =~ ^[1-9][0-9]*$ && $IPERF_PORT -le 65535 ]] || die "iperf-port 无效"
for cmd in sysbench fio iperf3 jq awk sort getconf; do need "$cmd"; done
[[ -d $DISK_DIR && -w $DISK_DIR ]] || die "磁盘目录不存在或不可写: $DISK_DIR"

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/linux-performance.XXXXXX") || die "无法创建临时目录"
TEST_FILE="$DISK_DIR/.linux-performance-fio.$$"
cleanup() {
    [[ -n ${TEST_FILE:-} && -f $TEST_FILE ]] && rm -f -- "$TEST_FILE"
    [[ -n ${TMP_DIR:-} && -d $TMP_DIR ]] && rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$(dirname -- "$OUTPUT")" || die "无法创建输出目录"
: >"$OUTPUT" || die "无法写入: $OUTPUT"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >&2; }
heading() { printf '\n===== %s =====\n' "$1" >>"$OUTPUT"; }
percentile() {
    local file=$1 pct=$2 count rank
    count=$(awk 'NF{n++}END{print n+0}' "$file")
    ((count>0)) || { printf 'N/A'; return; }
    rank=$(((count*pct+99)/100))
    sort -n "$file" | awk -v n="$rank" 'NR==n{print;exit}'
}

cpu_test() {
    local metrics="$TMP_DIR/cpu" raw="$TMP_DIR/raw" i value threads
    : >"$metrics"; threads=$(getconf _NPROCESSORS_ONLN)
    heading "CPU 原始数据（sysbench cpu）"; log "CPU 性能测试"
    for ((i=1;i<=TRIALS;i++)); do
        if sysbench cpu --threads="$threads" --time="$TEST_TIME" run >"$raw" 2>&1; then
            printf '\n--- CPU 第 %d/%d 轮 ---\n' "$i" "$TRIALS" >>"$OUTPUT"; cat "$raw" >>"$OUTPUT"
            value=$(awk '/events per second:/{print $4}' "$raw")
            [[ -n $value ]] || die "无法解析 CPU 第 $i 轮结果"; printf '%s\n' "$value" >>"$metrics"
        else cat "$raw" >>"$OUTPUT"; die "CPU 第 $i 轮失败"; fi
    done
}

memory_test() {
    local mode metrics raw="$TMP_DIR/raw" i value
    heading "内存原始数据（sysbench memory）"; log "内存性能测试"
    for mode in read write; do
        metrics="$TMP_DIR/memory_$mode"; : >"$metrics"
        for ((i=1;i<=TRIALS;i++)); do
            if sysbench memory --threads=1 --memory-oper="$mode" --memory-block-size=1M \
                --memory-total-size=100T --time="$TEST_TIME" run >"$raw" 2>&1; then
                printf '\n--- Memory %s 第 %d/%d 轮 ---\n' "$mode" "$i" "$TRIALS" >>"$OUTPUT"; cat "$raw" >>"$OUTPUT"
                value=$(awk -F'[()]' '/transferred/{gsub(/ MiB\/sec/,"",$2);print $2}' "$raw")
                [[ -n $value ]] || die "无法解析内存 $mode 第 $i 轮结果"; printf '%s\n' "$value" >>"$metrics"
            else cat "$raw" >>"$OUTPUT"; die "内存 $mode 第 $i 轮失败"; fi
        done
    done
}

fio_one() {
    local mode=$1 rw=$2 key raw="$TMP_DIR/fio.json" i
    local mi="$TMP_DIR/disk_${mode}_iops" mb="$TMP_DIR/disk_${mode}_bw" ml="$TMP_DIR/disk_${mode}_lat"
    : >"$mi"; : >"$mb"; : >"$ml"; [[ $mode == read ]] && key="read" || key="write"
    for ((i=1;i<=TRIALS;i++)); do
        if fio --name="$mode" --filename="$TEST_FILE" --size="$DISK_SIZE" --rw="$rw" --bs=4k \
            --iodepth=32 --numjobs=1 --direct=1 --ioengine=libaio --time_based=1 --runtime="$TEST_TIME" \
            --group_reporting=1 --output-format=json >"$raw" 2>&1; then
            printf '\n--- Disk %s 第 %d/%d 轮 ---\n' "$mode" "$i" "$TRIALS" >>"$OUTPUT"; cat "$raw" >>"$OUTPUT"
            jq -er ".jobs[0].$key.iops" "$raw" >>"$mi" || die "无法解析 fio IOPS"
            jq -er ".jobs[0].$key.bw_bytes/1048576" "$raw" >>"$mb" || die "无法解析 fio 带宽"
            jq -er ".jobs[0].$key.clat_ns.percentile[\"99.000000\"]/1000000" "$raw" >>"$ml" || die "无法解析 fio P99 延迟"
        else cat "$raw" >>"$OUTPUT"; die "磁盘 $mode 第 $i 轮失败（可能不支持 direct I/O/libaio）"; fi
    done
}

disk_test() {
    heading "磁盘原始数据（fio 4KiB 随机 I/O）"; log "磁盘性能测试：$TEST_FILE"
    fio_one read randread; fio_one write randwrite
    rm -f -- "$TEST_FILE"
}

network_one() {
    local mode=$1 reverse=$2 raw="$TMP_DIR/iperf.json" i
    local throughput="$TMP_DIR/network_$mode" retrans="$TMP_DIR/network_${mode}_retrans"
    : >"$throughput"; : >"$retrans"
    for ((i=1;i<=TRIALS;i++)); do
        local -a args=(-c "$IPERF_SERVER" -p "$IPERF_PORT" -t "$TEST_TIME" -P 4 -J)
        [[ -n $reverse ]] && args+=(-R)
        if iperf3 "${args[@]}" >"$raw" 2>&1; then
            printf '\n--- Network %s 第 %d/%d 轮 ---\n' "$mode" "$i" "$TRIALS" >>"$OUTPUT"; cat "$raw" >>"$OUTPUT"
            jq -er '.end.sum_received.bits_per_second/1000000' "$raw" >>"$throughput" || die "无法解析 iperf3 吞吐"
            jq -er '.end.sum_sent.retransmits//0' "$raw" >>"$retrans" || die "无法解析 iperf3 重传"
        else cat "$raw" >>"$OUTPUT"; die "网络 $mode 第 $i 轮失败，请检查服务端、端口和防火墙"; fi
    done
}

network_test() {
    heading "网络原始数据（iperf3，4 条 TCP 流）"; log "网络性能测试"
    network_one upload ""; network_one download reverse
}

summary() {
    heading "保守稳定性能汇总"
    {
        printf '规则: 吞吐/IOPS 取各轮 q25；P99 延迟和重传取各轮 q75。\n'
        printf 'CPU: %s events/s (q25)\n' "$(percentile "$TMP_DIR/cpu" 25)"
        printf '内存读取: %s MiB/s (q25)\n' "$(percentile "$TMP_DIR/memory_read" 25)"
        printf '内存写入: %s MiB/s (q25)\n' "$(percentile "$TMP_DIR/memory_write" 25)"
        printf '磁盘随机读: %s IOPS, %s MiB/s (q25), %s ms P99 latency (q75)\n' \
            "$(percentile "$TMP_DIR/disk_read_iops" 25)" "$(percentile "$TMP_DIR/disk_read_bw" 25)" "$(percentile "$TMP_DIR/disk_read_lat" 75)"
        printf '磁盘随机写: %s IOPS, %s MiB/s (q25), %s ms P99 latency (q75)\n' \
            "$(percentile "$TMP_DIR/disk_write_iops" 25)" "$(percentile "$TMP_DIR/disk_write_bw" 25)" "$(percentile "$TMP_DIR/disk_write_lat" 75)"
        printf '网络上传: %s Mbit/s (q25)，重传 %s 次 (q75)\n' "$(percentile "$TMP_DIR/network_upload" 25)" "$(percentile "$TMP_DIR/network_upload_retrans" 75)"
        printf '网络下载: %s Mbit/s (q25)，重传 %s 次 (q75)\n' "$(percentile "$TMP_DIR/network_download" 25)" "$(percentile "$TMP_DIR/network_download_retrans" 75)"
    } >>"$OUTPUT"
}

printf 'Linux 服务器性能测试报告\n主机: %s\n开始时间: %s\n测试轮数: %s\n每个子测试每轮时长: %ss\n' \
    "$(hostname)" "$(date '+%F %T %z')" "$TRIALS" "$TEST_TIME" >>"$OUTPUT"
printf '磁盘目录/文件大小: %s / %s\niperf3 服务端: %s:%s\n' \
    "$DISK_DIR" "$DISK_SIZE" "$IPERF_SERVER" "$IPERF_PORT" >>"$OUTPUT"
cpu_test; memory_test; disk_test; network_test; summary
printf '\n结束时间: %s\n' "$(date '+%F %T %z')" >>"$OUTPUT"
printf '测试完成：%s\n' "$OUTPUT"
