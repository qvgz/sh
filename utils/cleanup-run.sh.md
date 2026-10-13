`bash cleanup-run.sh command [args ...]`：在独立会话启动命令，结束或收到 HUP/INT/TERM 时向其进程组发送 TERM，约 0.5 秒后 KILL。

依赖 Linux `setsid`。正常返回子命令状态，信号返回 129/130/143。适用于前台程序；自行创建会话的后代不受管理，SIGKILL 无法触发清理。
