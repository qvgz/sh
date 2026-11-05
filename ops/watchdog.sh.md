```bash
# 脚本旁 watchdog.conf，每行：匹配串|启动命令
# ^/opt/app/bin/server( .*)?$|/opt/app/bin/server -c /opt/app/conf/server.conf >> /opt/app/logs/server.log 2>&1
# ^java .*-jar /opt/web/web\.jar|cd /opt/web && java -jar /opt/web/web.jar >> /opt/web/web.log 2>&1 &
nohup bash ops/watchdog.sh >/dev/null 2>&1 &
# 开机及守护自身保活：crontab，已在运行时因实例锁直接退出
# * * * * * /bin/bash /opt/ops/watchdog.sh >/dev/null 2>&1
```

写匹配串：先按守护方式手动启动一次，再以 `ps -eo args` 看到的实际命令行为准。

```bash
# 1. 手动执行启动命令
setsid bash -c 'cd /opt/app && /opt/app/bin/run.sh -c conf/app.conf >> /opt/app/logs/app.log 2>&1' </dev/null &
# 2. 查看实际命令行：脚本以解释器开头，重定向不在其中；bash -c 行是包装进程，不作为匹配对象
ps -eo pid,args | grep '[/]opt/app'
#    10 bash -c cd /opt/app && /opt/app/bin/run.sh -c conf/app.conf >> /opt/app/logs/app.log 2>&1
#    11 /bin/bash /opt/app/bin/run.sh -c conf/app.conf
# 3. 验证匹配串只命中业务进程（输出 11）
pgrep -f -- '^/bin/bash /opt/app/bin/run\.sh( .*)?$'
# 4. 写入 watchdog.conf
# ^/bin/bash /opt/app/bin/run\.sh( .*)?$|cd /opt/app && /opt/app/bin/run.sh -c conf/app.conf >> /opt/app/logs/app.log 2>&1
```

- 兼容 CentOS 5.11（Bash 3.2.25、procps 3.2.7、util-linux 2.13）及更新 Linux，依赖 pgrep、flock、setsid、date、sleep。
- 匹配串是 `pgrep -f` 扩展正则，匹配完整命令行，不能含 `|`。须匹配进程启动后实际命令行（`ps -eo args` 核对，脚本以解释器开头，如 `/bin/bash /opt/app/run.sh`），尽量以 `^` 和绝对路径锚定，避免用 `|` 时可用 `( .*)?$` 收尾；否则会匹配到 `tail -f`、`grep`、编辑器等进程而误判存活，或匹配不到而重复启动最多 3 个实例。CentOS 5 内核 `/proc/PID/cmdline` 只返回前 4096 字节，长参数（如 Java classpath）之后的内容匹配不到。
- 启动命令经 `bash -c` 执行，可用 `cd`、`&&`、重定向；未自行重定向的输出写入守护日志。配置等同 root 可执行代码，须限制写权限。
- 守护须从交互终端或 crontab 启动；在 rc.local 等脚本中用 `&` 后台启动时，守护会继承忽略 INT/QUIT 并传给业务进程，需先 `set -m`。
- 停止守护、删改配置不停止已启动的业务进程。守护日志不轮转，业务输出未重定向时会写入其中，需外部清理。

功能需求：
- 接受正整数检查间隔，默认 20 秒；日志 watchdog.log、锁 watchdog.lock 均在脚本旁，flock 防重复运行。
- 每轮重读配置，支持 0~N 条、空行、`#` 注释、行首空白、CRLF；缺少 `|`、匹配串或命令为空、pgrep 异常的行记录后跳过。
- 进程不存在时用 `setsid bash -c` 后台启动，不阻塞守护，子进程不继承配置与锁；同一配置行两次启动至少间隔 RETRY_INTERVAL（默认 30 秒，环境变量可改，须为非负整数）。
- 未恢复前最多启动 3 次，之后记录一次停止启动并继续检查；检查到进程存在时记录恢复并清零。启动、恢复、停止均写入守护日志；计数按配置行保存在内存，重启守护或修改该行即重置。
- INT/TERM 在当前 sleep 结束后退出。
