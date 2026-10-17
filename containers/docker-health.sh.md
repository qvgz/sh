```bash
DOCKER_NAME=app bash containers/docker-health.sh
DOCKER_NAME=app HEALTH_STATE_DIR=/var/lib/docker-health HEALTH_LOG_FILE=/var/log/docker-health.log bash containers/docker-health.sh
```

- 依赖 Docker 访问权限、`flock`；适合宿主机 cron 单轮调用。`DOCKER_NAME` 是容器名称前缀，不能为空。
- 状态目录默认脚本旁 `.docker-health-state`，日志默认脚本旁 `docker-health.log`；自定义相对路径以当前工作目录为准。同状态目录共用实例锁，锁冲突返回 0。
- `CMD` 由 `sh -c` 执行，必须可信；日志或回调失败不会撤销已完成的重启。无检查运行时删除对应容器 ID 状态文件可重置次数。

功能需求：
- 遍历所有容器，检查名称匹配前缀的容器。
  - running 且 healthy 或无 healthcheck：正常；有历史重启次数时记录 recovered，清零后执行恢复回调。
  - running starting、restarting、removing、paused：跳过。
  - 其余状态：先持久化次数，再执行 docker restart；每个容器最多尝试 3 次，失败也计数，恢复后清零。
- 重启日志包含时间、容器名、次数、结果、原状态；恢复日志包含时间、容器名、事件、状态。
- 回调环境包含 CONTAINER_NAME、CONTAINER_ID、CONTAINER_STATUS、CONTAINER_EVENT、EVENT_TIME、RESTART_TIME、RESTART_ATTEMPT、RESTART_RESULT、RECOVERY_TIME；不适用字段置空，恢复次数为 0。
- 检测到异常即返回非零，即使本轮重启成功；检查、状态写入、日志或回调失败也返回非零。
