`bash get-ip-info.sh IPv4`：查询地理信息并输出服务商 JSON；拒绝 RFC1918 私网地址。

依赖 `curl`、`jq`（现在必需）。依次查询 ipwho.is、DB-IP、ipinfo，单次最多 5 秒；HTTP 错误、无效 JSON、错误对象或地址不符时切换。字段随服务商变化。
