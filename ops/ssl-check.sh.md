# SSL 证书信息与到期检查

`bash ssl-check.sh [-v] 域名`：使用 SNI 查询 TCP 443 的叶证书；默认输出 issuer、subject、notBefore/notAfter，日期转为上海时区 YYYY-MM-DD；`-v` 输出证书全文。

`-f [清单] [-d [天数]]`：默认清单为脚本旁 `ssl-check.sh.txt`，显式路径不存在即失败；每行首列域名，忽略空行/注释。

生成 `清单.check.txt`（域名、上海时区到期日、日历剩余天数）；失败记 X、天数留空，X 置顶，其余按天数升序、列对齐，原报告原子覆盖。`-d` 默认 30，另生成 `清单.check.Nd.txt`，包含天数 ≤ N（含已过期）及 X；单独 `-d` 使用默认清单。任一行失败返回非零。

依赖 `openssl`、`timeout`/`gtimeout`（coreutils）、`awk`。连接最多 10 秒，超时后最多 1 秒强制终止；无自动重试。`SSL_CHECK_QUERY_INTERVAL` 默认 1 秒，仅在批量实际查询后等待；单次运行缓存成功和失败结果，重复域名不重复查询。仅读取证书信息，不验证信任链或主机名。
