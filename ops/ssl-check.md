# 检测 SSL 证书信息

需求描述：
  - ssl-check.sh <domain>
    - 只返回 issuer subject dates
    - dates 格式处理成 2026-04-26，并且为 Asia/Shanghai
  - ssl-check.sh [-v] <domain>
    - 不做处理，完整返回 text
  - ssl-check.sh [-f [file_path]] [-d [number]]
    [-f [file_path]] 从文件读取域名列表查询
      - 约定 file_path 文件有一列域名
      - file_path 不存在或没指定，尝试从脚本同目录 ssl-check.sh.txt 读取
      - 只查询域名 enddate 值
      - 查询结果写入 file_path.check.txt 中
      - file_path.check.txt 约定有三列
        - 第一列 域名
        - 第二列 enddate 日期，格式为 2026-04-26，并且为 Asia/Shanghai
          - 查询失败 enddate 值为 X
          - 获取不到 enddate 值为查询失败，查询失败间隔 1s 再次查询，最多查询 3 次
        - 第三列证书还有多少天到期
          - 查询失败第三列值为空
      - 最终 file_path.check.txt 按第三列升序排序，X 值置顶
      - file_path.check.txt 该文件存在覆盖不提醒
    [-d [number]] 筛选证书还有多少天到期的域名
      - number 为域名证书到期天数，缺省 30 天。
      - number 天内到期证书域名，写入 file_path.check.numberd.txt 中
      - 约定 file_path.check.numberd.txt 有三列，分别为 域名 enddate 还有多少天到期
      - enddate 为X 值置顶
  - 每个域名，只有一次成功的查询。
  - 不做命令依赖检查。
  - file_path.check.txt 与 file_path.check.numberd.txt 列对齐，更加直观。

  
  
