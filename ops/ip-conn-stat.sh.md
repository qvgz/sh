`bash ip-conn-stat.sh`：统计当前网络命名空间 ESTABLISHED TCP IPv4 连接，按远端和本地地址分别降序输出。

依赖 Linux iproute2 `ss`、POSIX `awk`、`sort`。过滤常见私网、共享、链路本地、文档、基准及保留范围；连接快照不能判断入站/出站方向。
