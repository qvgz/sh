```bash
bash utils/get-domain-ip-host.sh example.com
```

- 依赖 host、awk；只查 DNS，不读取 /etc/hosts。

功能需求：
- 接受且仅接受一个非空域名参数，拒绝以 - 开头或包含空白、斜线、冒号的输入。
- 使用 host 的系统 DNS 配置，超时 3 秒、一次尝试。
- 输出响应中首个 IPv4；查询失败或无可用地址返回非零，参数无效返回 2。
