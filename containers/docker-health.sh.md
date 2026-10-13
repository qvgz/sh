宿主机 cron 调用：`DOCKER_NAME=前缀 bash docker-health.sh`，单轮检查所有名称匹配容器。

需要 Docker 权限、`flock`。running healthy/无 healthcheck 视为正常；starting、restarting、removing、paused 跳过；其余异常最多重启 3 次，失败重启也计数，恢复后清零。计数原子写入，异常或操作失败返回非零。

`HEALTH_STATE_DIR` 默认脚本旁 `.docker-health-state`（含实例锁），`HEALTH_LOG_FILE` 默认 `docker-health.log`。`CMD` 为可信 shell 回调，重启/恢复后执行；环境含 CONTAINER_NAME/ID、CONTAINER_EVENT、EVENT_TIME、CONTAINER_STATUS 和 RESTART_* / RECOVERY_TIME。日志/回调失败不撤销已完成重启。

清除对应容器 ID 的状态文件可重置次数，需在无检查运行时执行；移除脚本不会回退容器操作。
