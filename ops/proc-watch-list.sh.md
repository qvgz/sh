Linux、Bash 4.1+；依赖 `flock`、`setsid`、`nohup`、GNU `stat`。`bash proc-watch-list.sh [间隔秒数]`，默认 3。

脚本旁 `proc-watch-list.txt` 每行一个可执行文件绝对路径及参数：

```text
/opt/service/server --port 8080
/opt/exporter --exclude='^/(sys|proc)($|/)' &> /dev/null
```

- 支持空行、注释、CRLF、单/双引号和空参数；双引号内仅转义 `\"`、`\\`，不做 shell 展开。只允许行尾 `&> /dev/null` 重定向。
- 每轮重读配置、按完整 argv 去重匹配 `/proc`；需使用前台程序。自行 daemonize、改 argv 或 `/proc` 不可见可能重复启动。
- 程序在自身目录运行，输出到 `程序名.log`；守护日志在脚本旁。超过 512 MiB 复制为 `.bak` 并截断，只留一份；复制期间可能丢输出。
- 实例锁在脚本旁，运行中勿删除。单条配置故障跳过，配置读取或守护日志失败退出；停止守护/移除配置不停止业务，修改配置不重启已有进程。
