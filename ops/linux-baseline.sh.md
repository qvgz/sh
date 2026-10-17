```bash
bash ops/linux-baseline.sh
bash ops/linux-baseline.sh --duration 10 --output load.txt
```

- 依赖 Linux /proc、/sys、awk 等基础命令；各类依次采样，总时长约为 duration 的 4 倍，窗口不同。
- 整盘含虚拟设备层，不应将各层吞吐相加；峰值为单设备/网卡采样峰值。

功能需求：
- --duration 指定每类采样秒数，默认 25，须为正整数。
- 每秒采集 CPU 使用率（idle 含 iowait）、内存可用量/使用率及 swap 使用量、整盘吞吐/IOPS/利用率、网卡收发吞吐。
- 跳过分区及 loop、ram、fd、sr 数字编号设备；磁盘和网卡速率按实际采样间隔计算。
- 报告包含原始数据和最高负载汇总；--output 指定报告，默认当前目录 linux_load_主机_时间.txt，拒绝覆盖。
- 失败停止，保留已写报告并清理临时目录。
