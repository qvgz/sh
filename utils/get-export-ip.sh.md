```bash
bash utils/get-export-ip.sh
```

- 依赖 curl；沿用 curl 代理环境，单接口连接超时 3 秒、总超时 5 秒，6 个接口全部失败最多约 30 秒。

功能需求：
- 随机打乱 api.ipify.org、ip.3322.net、ifconfig.me、ip.sb、checkip.amazonaws.com、whatismyip.akamai.com 六个 HTTPS 接口，每个最多查询一次。
- curl -4 请求，HTTP 错误或响应不是合法 IPv4 则切换；去除回车后输出首个有效结果并返回 0。
- 缺少 curl 或全部失败返回 1；只校验 IPv4 格式，不额外检查地址是否公网。
