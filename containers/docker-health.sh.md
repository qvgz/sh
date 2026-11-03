```bash
bash containers/docker-health.sh
HEALTH_STATE_DIR=/var/lib/docker-health HEALTH_LOG_FILE=/var/log/docker-health.log bash containers/docker-health.sh
```

- 依赖 Docker 访问权限、`flock`；容器需配置 healthcheck；适合宿主机 cron 单轮调用。
- 状态目录默认脚本旁 `.docker-health-state`，日志默认脚本旁 `docker-health.log`；自定义相对路径以当前工作目录为准。同状态目录共用实例锁，锁冲突返回 0。
- `CMD` 由 `sh -c` 执行，必须可信；日志或回调失败不会撤销已完成的重启。无检查运行时删除对应容器 ID 状态文件可重置次数。

功能需求：
- 检查所有 running 容器；退出由 restart 策略（如 `unless-stopped`）负责，人工停止的容器不处理。
  - unhealthy：先持久化次数，再执行 docker restart；每个容器最多尝试 3 次，失败也计数。
  - healthy：有历史重启次数时记录 recovered，清零后执行恢复回调。
  - starting、无 healthcheck：跳过。
- 重启日志包含时间、容器名、次数、结果、原状态；恢复日志包含时间、容器名、事件、状态。
- 回调环境包含 CONTAINER_NAME、CONTAINER_ID、CONTAINER_STATUS、CONTAINER_EVENT、EVENT_TIME、RESTART_TIME、RESTART_ATTEMPT、RESTART_RESULT、RECOVERY_TIME；不适用字段置空，恢复次数为 0。
- 检测到 unhealthy 即返回非零，即使本轮重启成功；检查、状态写入、日志或回调失败也返回非零。
