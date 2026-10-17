```bash
bash ops/analyze-baseline.sh --iperf-server 192.0.2.10
bash ops/analyze-baseline.sh --iperf-server 192.0.2.10 --trials 3 --time 10 --disk-dir /data --disk-size 1G --output performance.txt
```

- Linux 依赖 sysbench、fio（支持 libaio）、iperf3、jq、awk、sort、getconf；对端需运行 iperf3 -s。
- 主动压测会产生高 CPU、磁盘写入和网络负载；结果只代表当前参数下表现。失败保留部分报告，退出清理临时文件。

功能需求：
- 必须指定 --iperf-server；--iperf-port 默认 5201。
- --trials 默认 5，至少 3；--time 默认 15 秒；--disk-dir 默认 /tmp，--disk-size 默认 1G。
- 依次执行 7 项测试，每项重复指定轮数：CPU、单线程内存读/写、4KiB 随机磁盘读/写、网络上传/下载。
  - CPU 使用全部在线处理器；fio 使用 direct I/O、libaio、队列深度 32、单 job；网络使用 4 条 TCP 流。
- 报告保留原始结果，吞吐/IOPS 取各轮 q25，P99 延迟/重传取 q75。
- --output 指定报告，默认当前目录 linux_performance_主机_时间.txt；拒绝覆盖已有报告。
