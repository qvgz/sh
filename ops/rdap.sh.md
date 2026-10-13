# 域名信息与到期检查

`bash rdap.sh [-v] 域名`：优先 WHOIS，失败后按 [IANA 权威 RDAP 列表](https://www.iana.org/assignments/rdap-dns) 依次查询；无 expiration 的响应继续尝试下一接口。

- 默认输出两列：expiration、last changed、registration 对应日期，以及首个 nameservers 名称；缺失字段省略。`-v` 输出 WHOIS 原文或格式化 RDAP JSON。
- 输入支持域名、子域名或 HTTP(S) URL；自动提取两级根域名，常见 `.cn` 二级后缀保留三级。其他公共后缀须调整 `root_domain`；IDN 使用 Punycode。
- WHOIS 字段映射：Registry Expiry Date/Expiration Time → expiration，Updated Date → last changed，Creation Date/Registration Time → registration，Name Server → nameservers。

`-f [清单] [-d [天数]]`：清单默认脚本旁 `rdap.sh.txt`，显式路径不存在即失败；每行首列域名，忽略空行/注释。

生成 `清单.check.txt`（原域名、YYYY-MM-DD 到期日、剩余天数）；失败记 X、天数留空，X 置顶，其余按天数升序、列对齐，原报告原子覆盖。`-d` 默认 30，另生成 `清单.check.Nd.txt`，包含天数 ≤ N（含已过期）及 X；单独 `-d` 使用默认清单。任一行失败返回非零。

依赖 `curl`、`jq`、`awk`；WHOIS 可选，需 `whois` 和 `timeout`/`gtimeout`。WHOIS 最多 10 秒，IANA 列表最多 10 秒，各 RDAP 请求最多 8 秒，无自动重试。`RDAP_QUERY_INTERVAL` 默认 3 秒，仅在批量实际查询后等待；单次运行缓存成功和失败结果，重复根域名不重复查询。天数按本地日历日期比较。
