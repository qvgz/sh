```bash
bash ops/log-clean.sh /var/log/nginx
bash ops/log-clean.sh -k 30 /var/log/myapp 'kill -HUP "$(cat /run/myapp.pid)"'
bash ops/log-clean.sh -t /var/log/debug   # 只清空，不留本地备份
# crontab 每日 0 点后执行
# 5 0 * * * /bin/bash /opt/ops/log-clean.sh /var/log/nginx >>/var/log/log-clean.err 2>&1
```

- 最低兼容 CentOS 7.9.2009（Bash 4.2、coreutils 8.22、findutils 4.5、util-linux 2.23、gzip 1.5）；依赖 GNU date/find/truncate/mktemp、flock、gzip；按 Asia/Shanghai（无夏令时）计算昨日日期；重开命令由 bash -c 执行，必须可信。
- 复制后清空原文件（同 logrotate copytruncate），路径不变，不中断采集；复制结束到清空之间写入的行不进备份。采集端须支持文件被清空后从头读（Vector、Fluent Bit、Filebeat 默认支持），清空前未读到的行会漏采。
- 写入进程须以追加模式（O_APPEND）打开日志，如 nginx、shell `>>`；否则清空后从原偏移继续写，文件头出现空洞，需配置重开命令。核对：`/proc/<pid>/fdinfo/<fd>` 的 flags 含 02000。
- 压缩、清空及过期删除不自动回退。锁文件位于日志目录，运行中勿删除。过期按 backup/YYYYMMDD 目录名整个删除，勿在日期目录中存放其他文件。

功能需求：
- 参数：`[-k 保留天数] [-t] 日志目录 [重开命令]`，保留天数为正整数，默认 90；选项须在日志目录前，重开命令不能以 `-` 开头；参数错误或目录不存在返回 2，锁冲突返回 1；改动文件前校验保留天数可计算。
- 将顶层非空普通 .log 文件（不含空文件、符号链接、子目录）gzip 复制为 backup/昨日YYYYMMDD/名称.log.gz，重名依次加 .1.log.gz 等序号，不覆盖已有备份；先写 .tmp 再改名，压缩失败删除临时文件、不清空原文件并返回 1。
- 每个文件压缩成功后清空原文件。
- `-t`（默认关闭）：不备份，直接清空上述文件；重开命令与过期清理照常。
- 有文件备份或清空时执行重开命令，不继承锁；失败继续过期清理，最终返回其退出码。无非空 .log 时不执行。
- 只处理 backup/ 下 YYYYMMDD 目录：日期早于“今天减保留天数”的整个删除；非日期目录、符号链接不动。
