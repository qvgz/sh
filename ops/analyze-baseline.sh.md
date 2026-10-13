`bash analyze-baseline.sh --iperf-server HOST [选项]`：主动压测 CPU、内存、4K 随机磁盘和双向网络，产生高负载及临时磁盘写入。

Linux 依赖 `sysbench`、真正的 fio（libaio）、`iperf3`、`jq`。服务端需运行 `iperf3 -s`；`--disk-dir` 默认 `/tmp`、`--disk-size` 默认 `1G`、`--iperf-port` 默认 5201。

`--trials` 默认 5（至少 3）；`--time` 默认 15 秒，每轮共 7 项测试。`--output` 指定新报告，拒绝覆盖；保留原始结果，吞吐/IOPS 取 q25、P99 延迟/重传取 q75。仅代表当前参数下表现；失败保留部分报告并清理临时文件。
