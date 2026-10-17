```bash
# 先在 ops/proc-watch-list.txt 中配置，例如：
# /opt/service/server --port 8080
# /opt/exporter --exclude='^/(sys|proc)($|/)' &> /dev/null
bash ops/proc-watch-list.sh 15
```

- 需要 Linux、可读 /proc、Bash 4.1+，依赖 flock、setsid、nohup、GNU stat 等基础命令。程序必须以前台方式运行；自行 daemonize、改 argv 或 /proc 不可见可能重复启动。
- 停止守护、删除或修改配置不停止已有业务进程。锁位于脚本旁，运行中勿删除；不同参数的同一程序共用程序日志。
- 日志超过 512 MiB 时复制为 .bak 后截断，只保留一份；复制期间可能丢输出。

功能需求：
- 接受正整数检查间隔，默认 15 秒；读取脚本旁 proc-watch-list.txt，守护日志为 proc-watch-list.log。
- 每轮重读清单，每行一个可执行普通文件绝对路径及参数；支持空行、整行注释、CRLF、单双引号、空参数。
  - 不做 shell 展开，双引号内仅转义双引号和反斜线；仅支持独立行尾 &> /dev/null，不支持管道或其他重定向。
- 按完整 argv 去重并匹配 /proc/cmdline，脚本允许解释器前缀；未运行时在程序目录用 setsid nohup 启动，输出追加至 程序名.log 或 /dev/null。
- 下轮仍未发现进程计一次失败；无法打开输出也计失败，连续 3 次后记录日志并停止重启，继续检查恢复。
- 发现恢复时记录日志并清零次数，之后退出可重新尝试；计数按 argv 保存在内存，重启守护重置。
- 单条配置错误记录后跳过；配置读取、守护日志或实例锁失败退出；INT/TERM 停止守护，已启动业务保留。
