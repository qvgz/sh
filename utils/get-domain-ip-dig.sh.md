`bash get-domain-ip-dig.sh 域名`：输出首个 IPv4；查询失败或无 A 记录返回非零。

依赖 `dig`、`awk`。固定查询 1.0.0.1，超时 2 秒、一次尝试。
