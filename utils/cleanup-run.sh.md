```bash
bash utils/cleanup-run.sh command arg1 arg2
```

- 依赖 Bash 作业控制，无需 setsid；适用于前台程序，自行创建进程组或会话的后代不受管理，SIGKILL 无法触发清理。

功能需求：
- 至少提供一个命令参数，按原 argv 在独立进程组启动并等待。
- 命令结束或收到 HUP/INT/TERM 时，向该进程组发送 TERM，最多等待约 0.5 秒后发送 KILL 并回收子进程。
- 正常返回子命令状态；HUP/INT/TERM 分别返回 129/130/143，无参数返回 2。
