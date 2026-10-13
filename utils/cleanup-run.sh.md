`bash cleanup-run.sh command [args ...]`：通过 Bash 作业控制在独立进程组启动命令，结束或收到 HUP/INT/TERM 时向其进程组发送 TERM，约 0.5 秒后 KILL。

无需 `setsid`。正常返回子命令状态，信号返回 129/130/143。适用于前台程序；自行创建进程组或会话的后代不受管理，SIGKILL 无法触发清理。
