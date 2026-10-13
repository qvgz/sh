`bash linux-baseline.sh [--duration 25] [--output 新报告文件]`：依次采集 CPU、内存、整盘 I/O、网卡负载，总时长约为 duration 的 4 倍。

依赖 Linux `/proc`、`/sys` 和 `awk`。输出原始采样及峰值，拒绝覆盖已有报告；磁盘/网络速率按实际采样间隔计算。忽略分区及 loop/ram 等设备，整盘含虚拟层，汇总不应相加；各类采样窗口不同。
