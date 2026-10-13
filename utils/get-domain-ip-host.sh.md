`bash get-domain-ip-host.sh 域名`：输出首个 IPv4；查询失败或无 A 记录返回非零。

依赖 `host`、`awk`。使用 host 的系统 DNS 配置，超时 3 秒、一次尝试；不读取 /etc/hosts。
