```bash
bash ops/log-clean.sh /var/log/myapp
bash ops/log-clean.sh /var/log/nginx 'kill -USR1 "$(cat /run/nginx.pid)"'
```

- 依赖 Linux GNU date/find、flock、mktemp；重开命令由 bash -c 执行，必须可信。服务须能重开日志，否则继续写入备份。
- 移动及历史删除不自动回退；恢复文件前停止写入。锁文件位于日志目录，运行中勿删除。

功能需求：
- 接受日志目录和可选重开日志命令；目录不存在返回 2，锁冲突失败。
- 将顶层普通 .log 文件移到 backup/昨日YYYYMMDD/，重名依次增加 .1.log 等序号，不覆盖已有备份。
- 移动完成后执行重开命令；失败立即停止，不清理历史备份。
- 删除 backup 下 mtime +90 的普通 .log 文件及空子目录，保留 backup 根目录；保留期固定，不可传参。
