```bash
bash utils/cleanup-run.sh command arg1 arg2
CLEANUP_RUN_GRACE=5 bash utils/cleanup-run.sh command   # 宽限 5 秒
```

- 依赖 Bash 作业控制，无需 setsid；自行创建进程组或会话的后代不受管理，SIGKILL 无法触发清理。
- 不支持交互命令：子命令在后台进程组，stdin 为终端时改接 `/dev/null`。
- 启动时已被忽略的信号（如 `nohup` 的 HUP、非交互 shell 中 `&` 启动时的 INT）无法捕获。

功能需求：
- 至少提供一个命令参数，按原 argv 在独立进程组启动并等待。
- 收到 HUP/INT/TERM 时向进程组转发同一信号；子命令自行结束时向残留后代发送 TERM。随后发送 CONT，宽限期（`CLEANUP_RUN_GRACE` 秒，最多 1 位小数，默认 0.5）内未退出则 KILL，并回收子进程。
- 正常返回子命令状态；收到信号时清理后以同一信号终止自身（shell 中 `$?` 为 129/130/143）；无参数或宽限值无效返回 2。
