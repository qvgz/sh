# 网宿 CDN 刷新

[接口文档](https://apiexplorer.wangsu.com/apiexplorer/doc?productType=all_product&language=ZH_CN&apiId=4515&rsr=ws)

注意：该接口不会验证文件/文件夹是否存在，只要域名 CDN 存在且在网宿，接口就不会失败。

关联 wangsu-cdn-refresh.sh

需求描述：
  - wangsu-cdn-refresh.sh <[urls=]url1 url2>
    - 脚本执行必须有参数。
    - 参数是 1～N 个 url，url 间隔空格或换行，也可能是 “urls=url1 url2” 形式，只是开头多了 urls=。
    - 约定 url 末尾不是 / 为文件 url，例如 https://abc.com/file，对应接口 Body 参数 urls。
    - 约定 url 末尾是 / 为文件夹 url，例如 https://abc.com/dir/，对应接口 Body 参数 dirs。
  - 提取参数填充对应接口 Body 参数，填充完所有参数 url，再请求接口，N 个参数 url，只请求 1 次接口。
  - 不存在文件 url，接口 Body 不需要参数 urls urlAction。
  - 不存在文件夹 url，接口 Body 不需要参数 dirs dirAction。
  - 接口请求超时，重试一次。
  - 接口返回 json 文件，例如：{"Code":1,"Message":"handle success","itemId":"xxx"}
    - 检查接口返回，Code 等于 0 时，脚本退出码为 1。Code 等于 1 时，脚本退出码为 0。
  - username apiKey 从外部变量读取。
