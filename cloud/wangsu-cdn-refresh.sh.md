# 网宿 CDN 刷新

`WS_USERNAME=... WS_APIKEY=... bash wangsu-cdn-refresh.sh [urls=]URL ...`

- 至少一个 HTTP(S) URL；支持多个参数或一个空格/换行分隔参数，URL 内空格须编码。
- 末尾 `/` 归入 `dirs`，动作 `expire`；其余归入 `urls`，动作 `delete`。没有对应 URL 时省略该组字段，整批只提交一次。
- HTTP 成功且响应 JSON `Code` 为数字 `1` 时返回 0；`Code=0` 返回 1，其他错误返回非零。提交成功不代表源站文件/目录存在。
- 连接超时 10 秒、请求最多 30 秒；超时不自动重试，先核实平台任务记录，避免重复提交。刷新无法撤销。

依赖 `curl`、`openssl`、`jq`；认证临时文件仅当前用户可读写，退出清除。[接口文档](https://apiexplorer.wangsu.com/apiexplorer/doc?productType=all_product&language=ZH_CN&apiId=4515&rsr=ws)。
