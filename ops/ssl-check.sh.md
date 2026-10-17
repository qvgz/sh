```bash
bash ops/ssl-check.sh example.com
bash ops/ssl-check.sh -v example.com
bash ops/ssl-check.sh -f domains.txt -d 30
bash ops/ssl-check.sh -d
```

- 依赖 openssl、timeout/gtimeout、awk 等基础命令和 GNU/BSD date；连接限时 10 秒，再给 1 秒强制终止，不自动重试。
- 仅读取叶证书，不验证信任链或主机名；输入为主机名，不接受 URL 或自定义端口。
- SSL_CHECK_QUERY_INTERVAL 默认 1 秒，支持非负小数；报告覆盖同名旧报告，日期和剩余日历天数使用 Asia/Shanghai。

功能需求：
- 单域名使用 SNI 连接 TCP 443；默认输出 issuer、subject、notBefore、notAfter，日期转为 YYYY-MM-DD，转换失败保留原日期。
- -v 输出证书全文。
- -f [清单] 启用批量，默认脚本旁 ssl-check.sh.txt；显式路径须可读。每行首列为域名，忽略空行和注释。
- 生成 清单.check.txt：域名、上海时区到期日、剩余天数；失败写 X 且天数留空，X 置顶，其余按天数升序并对齐列，原子替换报告。
- -d [天数] 默认 30，生成全量报告及 清单.check.Nd.txt，包含天数 ≤ N（含已过期）和 X；单独 -d 使用默认清单。
- 同次运行缓存成功及失败结果，去掉末尾点后的重复域名不重复查询（区分大小写），仅实际批量查询后等待；任一条失败返回非零。
