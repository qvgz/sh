```bash
bash utils/get-ip-info.sh 1.1.1.1
```

- 依赖 curl、jq；单接口连接超时 3 秒、总超时 5 秒，9 个接口最多约 45 秒，其中 ip-api 使用 HTTP。
- 当前请求未拼接输入 IP，仅访问数组中的基础 URL；多数接口无法据此查询指定地址，可能全部失败。输入 IP 仅用于响应匹配。

功能需求：
- 接受且仅接受一个合法 IPv4，拒绝 RFC1918 私网地址；不全面排除其他特殊用途地址。
- 随机打乱 DB-IP、ip-api、ipinfo、ipwho.is、ip.guide、reallyfreegeoip、ipbase、myip.ipip.net、v4.yinghualuo.cn 九个 URL，每个最多查询一次。
- HTTP 成功且响应是 JSON 对象、success 不为 false、error 为 null、ip 或 ipAddress 等于输入时，格式化输出 JSON 并返回。
- 字段结构随接口变化；输入无效返回 2，私网地址、依赖缺失或全部失败返回 1。
