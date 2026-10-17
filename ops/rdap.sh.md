```bash
bash ops/rdap.sh example.com
bash ops/rdap.sh -v https://www.example.com/
bash ops/rdap.sh -f domains.txt -d 30
bash ops/rdap.sh -d
```

- 依赖 curl、jq、awk 及 GNU/BSD date；WHOIS 可选，需 whois 和 timeout/gtimeout。WHOIS 限时 10 秒（再给 1 秒强制终止），IANA 列表最多 10 秒，各 RDAP 请求最多 8 秒，不自动重试。
- 根域名按最后两级提取，仅 ac.cn/com.cn/edu.cn/gov.cn/net.cn/org.cn 保留三级；其他公共后缀需调整脚本，IDN 需使用 Punycode。
- 批量查询间隔 RDAP_QUERY_INTERVAL 默认 3 秒，支持非负小数；报告覆盖同名旧报告，剩余天数按本地日历日期计算。

功能需求：
- 单域名接受域名、子域名或 HTTP(S) URL；优先 WHOIS，有到期字段才采用，否则按 IANA RDAP DNS 列表依次尝试 HTTPS 接口。
- RDAP 响应须为 domain、无 errorCode 且有有效 expiration 日期，否则继续下一接口。
- 默认输出两列 expiration、last changed、registration、首个 nameservers，缺失项省略；-v 输出 WHOIS 原文或格式化 RDAP JSON。
  - WHOIS 映射 Registry Expiry Date/Expiration Time、Updated Date、Creation Date/Registration Time、Name Server。
- -f [清单] 启用批量，默认脚本旁 rdap.sh.txt；显式路径须可读。每行首列作为输入，忽略空行和注释。
- 生成 清单.check.txt：原输入、YYYY-MM-DD 到期日、剩余天数；失败写 X 且天数留空，X 置顶，其余按天数升序并对齐列，原子替换报告。
- -d [天数] 默认 30，生成全量报告及 清单.check.Nd.txt，保留天数 ≤ N（含已过期）和 X；单独 -d 使用默认清单。
- 同次运行缓存成功及失败结果，重复根域名不重复查询，仅实际批量查询后等待；任一条失败返回非零。
