```bash
WS_USERNAME=账号 WS_APIKEY=密钥 bash cloud/wangsu-cdn-refresh.sh https://example.com/a.css https://example.com/assets/
WS_USERNAME=账号 WS_APIKEY=密钥 bash cloud/wangsu-cdn-refresh.sh 'urls=https://example.com/a.css https://example.com/b.js'
```

- 依赖 curl、openssl、jq；认证临时文件仅当前用户可读写，退出清理。URL 内空格需编码。
- 连接超时 10 秒、请求最多 30 秒，不自动重试；失败或超时先核实平台记录。刷新不可撤销，提交成功不代表源站资源存在。

功能需求：
- 至少提供一个 HTTP(S) URL，支持多个参数或空白分隔的一段参数；各参数可带 urls= 前缀。
- 末尾 / 的 URL 放入 dirs，dirAction=expire；其余放入 urls，urlAction=delete；空组省略。
- 使用 WS_USERNAME、WS_APIKEY 和 GMT 请求时间生成认证，一次提交整批刷新请求。
- HTTP 请求成功后输出响应，仅 JSON Code 为数字 1 时返回 0；其他响应或请求失败返回非零。
