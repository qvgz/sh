```bash
FILE=/var/log/app/app.log PATTERN='ERROR*timeout' CMD='systemctl restart app' bash ops/log-trigger.sh
# 60 秒内命中 10 次算一次触发，5 分钟内只执行一次；MATCH_LINE 为触发时的匹配行
FILE=/var/log/app/app.log PATTERN='OutOfMemory' HITS=10 WINDOW=60 SUPPRESS=300 \
  CMD='bash /opt/ops/wechat2.sh "$MATCH_LINE"' nohup bash ops/log-trigger.sh >>/var/log/log-trigger.log 2>&1 &
# 日志示例
# [2026-11-08 10:00:00] 匹配: java.lang.OutOfMemoryError | 执行成功
# [2026-11-08 10:05:12] 匹配: java.lang.OutOfMemoryError | 执行失败 rc=1
# <命令完整输出>
# [2026-11-08 10:10:30] 匹配: java.lang.OutOfMemoryError | 执行超时 60s rc=124
# <超时前已有输出>
```

- 最低兼容 CentOS 7.9.2009（Bash 4.2、coreutils 8.22、grep 2.20），依赖 GNU tail（`-F --pid`）、grep、sed。
- CentOS 7 的 tail 8.22 不识别 overlayfs 等文件系统，文件被删除、轮转重建后报 `replaced with a remote file` 并停止跟踪，容器内监控须挂载卷；ext4、xfs、tmpfs 正常。
- 命令由 `bash -c` 后台执行，不阻塞监控，必须可信；日志在命令结束后写出，长时间运行的命令日志随之延后。命令中后台启动的常驻进程须重定向输出（`>/dev/null 2>&1 &`），否则占用输出管道，该次执行结果永不输出。
- 超时由 coreutils `timeout` 对整个进程组发信号，命令中启动的子进程（含后台进程）一并终止；`TIMEOUT>0` 时命令自身以 124/137 退出也会记为超时。
- `SUPPRESS=0` 且 `HITS=1` 时每条匹配行起一个进程，日志暴增会大量并发执行命令。
- tail 的诊断信息（文件截断、不存在、放弃跟踪等）写标准错误，与执行日志分开。
- 命中计数与抑制时间只保存在内存，重启即重置。

功能需求：
- 环境变量：必须 `FILE`、`PATTERN`、`CMD`；可选 `HITS`（正整数，默认 1）、`WINDOW`（秒，非负整数，默认 60，0 不清零）、`SUPPRESS`（秒，非负整数，默认 60，0 不抑制）、`TIMEOUT`（秒，非负整数，默认 60，0 不限制）、`TZ`（日志时区，默认 Asia/Shanghai，命令同样继承）。缺失或非法返回 2。
- 等同 `tail -n0 -F FILE | grep --line-buffered`：只看启动后新增行，文件不存在时等待创建，轮转后跟踪新文件；按字节子串匹配，`*` 匹配任意字符串（含 GBK 等非 UTF-8 内容），`?` 匹配单个字节（一个 UTF-8 汉字为 3 字节），其他字符按字面；`PATTERN` 不能含换行。
- 计数窗口从首次命中开始，`WINDOW` 秒内累计 `HITS` 次命中算一次触发并清零；窗口过期未达次数则清零，以当前命中开始新窗口。
- 距上次执行不足 `SUPPRESS` 秒的触发不执行、不记录。执行时命令可用 `$FILE` 及导出的 `MATCH_LINE`（本次触发的最后一条匹配行）。
- 命令执行超过 `TIMEOUT` 秒发 TERM，再过 5 秒未退出发 KILL。
- 日志只在执行命令时输出一条到标准输出：触发时间、匹配行、执行结果（成功、失败、超时）；成功不输出命令输出，失败、超时附退出码及完整 stdout/stderr。
- 持续运行，脚本退出后 tail 随之退出。
