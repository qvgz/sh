关联同目录 docker-health.sh

# 功能需求：
- 循环执行依赖系统 cron
- 设定需要检查的 docker_name
- 检查所有 NAMES 为 docker_name* 的容器
  - STATUS 不为 UP 或不为 UP healthy
    - 重启该容器
    - 最多只重启3次
    - 记录重启 时间 容器名 到 docker-health.log
    - 执行设定的 CMD 命令
  - STATUS 恢复为 UP 或 UP healthy
    - 记录恢复 时间 容器名 到 docker-health.log
    - 执行设定的 CMD 命令

# 使用示例
cron 示例（每分钟执行一次，替换为实际绝对路径；确保 cron PATH 含 docker、flock）：
```cron
* * * * * DOCKER_NAME=skipping-rope- /bin/sh /absolute/path/docker-health.sh
```

自定义命令示例：
```sh
export DOCKER_NAME=skipping-rope-
export CMD='printf "%s %s %s\n" "$EVENT_TIME" "$CONTAINER_EVENT" "$CONTAINER_NAME"'
/bin/sh ./docker-health.sh
```

# 实现与配置：
- 在宿主机运行，需要 Docker CLI、访问 Docker 的权限及 `flock`。
- `DOCKER_NAME`：容器名称的字面前缀，默认 `skipping-rope-`；包含已停止容器。
- 正常状态：running 且没有 HEALTHCHECK，或 running 且 healthy。
  unhealthy、starting、exited、paused 等其他状态均尝试重启。
- 每个容器（按 ID）连续异常期间最多尝试重启 3 次，失败也计数。
  次数跨 cron 执行保存；观察到正常状态后清零，重新创建的容器独立计数。
- `HEALTH_STATE_DIR`：计数及执行锁目录，默认脚本旁的 `.docker-health-state`。
  请使用固定目录，并由同一系统用户运行；重叠执行会直接退出。
- `HEALTH_LOG_FILE`：默认脚本旁的 `docker-health.log`；每次重启尝试记录时间、
  容器名、次数、结果及原状态，不自动轮转日志。
  曾尝试重启的容器在后续检查中恢复正常时，记录时间、容器名、
  `event=recovered` 及当前状态，然后清零计数；持续正常不会重复记录。
  恢复日志写入失败时保留计数，下次检查重试；日志写入并清零成功后执行 CMD。
- `CMD`：每次重启尝试后、每次确认恢复后执行的 shell 命令，默认不执行。
  可读取环境变量 `CONTAINER_NAME`、`CONTAINER_ID`、`RESTART_TIME`、
  `RESTART_ATTEMPT`、`RESTART_RESULT`（success/failed）、`CONTAINER_STATUS`。
  `CONTAINER_EVENT` 为 `restart` 或 `recovered`，用于区分事件。
  `EVENT_TIME` 为当前事件时间（如 `2026-10-11T19:05:00+0800`），
  重启和恢复均可通过 `EVENT_TIME`、`CONTAINER_EVENT`、`CONTAINER_NAME`
  读取时间、事件类型和容器名。定义 CMD 时使用单引号，变量在执行时展开。
  恢复时 `RECOVERY_TIME` 为恢复时间，`RESTART_TIME`、`RESTART_RESULT` 为空，
  `RESTART_ATTEMPT` 为 0；重启时 `RECOVERY_TIME` 为空。
  恢复 CMD 失败时返回非零，计数保持清零，持续正常时不重复执行。
  持续异常达到上限后不再重启、追加日志或执行 CMD；之后恢复仍记录日志并执行 CMD。
- Docker 查询、重启、计数写入、日志或 CMD 失败时返回非零；会继续处理其他容器。


