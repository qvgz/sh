`bash get-export-ip.sh`：输出出口 IPv4，全部失败返回非零。

依赖 `curl`；顺序尝试三个 HTTPS 接口，单次最多 5 秒、总计约 15 秒，沿用 curl 代理环境。
