
```bash
./compose-update.sh APP_TAG v2
./compose-update.sh APP_TAG v2 -t
ENV_FILE=.env.custom LOG_FILE=env-update.log ./compose-update.sh APP_TAG v2
```

- 依赖 Bash、Docker Compose v2、Mike Farah yq v4 和 `flock`。环境文件默认同目录 `.env.prod`，日志默认同目录 `env-update.log`；相对路径以脚本目录为准。
- 使用独立的 `env_file.lock` 防并发，冲突立即失败；环境文件须已存在且不是符号链接。
- 临时覆盖标签执行 `up -d`，成功后才保存环境文件；不额外检查健康。仅启动失败时尝试回滚；保存失败不回滚，记录异常并返回非零。“回滚”日志仅代表已尝试回滚。`-t` 同样检查旧值存在、非空且不同于新值。
- 在脚本目录执行 Compose，不指定 `-f`，由 Compose 自动查找配置；镜像从 `config --no-interpolate` 输出提取。命令显式传入 `--env-file`。标签必须是合法的字面量，不解析旧值中的变量引用。

功能需求：
- ./compose-update.sh <TAG_NAME> <TAG_VALUE> [-t]
  - env_file 中不存在 TAG_NAME，TAG_VALUE_OLD 值为空，TAG_VALUE=TAG_VALUE_OLD，错误退出
  - 从 Compose 自动选择的配置提取使用 ${TAG_NAME} 的 image，允许多个服务共用，格式为 `仓库:${TAG_NAME}`
  - 执行 docker pull image:TAG_VALUE 成功
    - 执行 TAG_NAME=TAG_VALUE docker compose up -d 成功
      - 更新 env_file 文件中 TAG_NAME 值为 TAG_VALUE，该文件缺省同目录 .env.prod
      - 保存失败不回滚，返回非零退出码；日志格式：时间 异常 image:TAG_VALUE 标签更新失败
    - 执行 TAG_NAME=TAG_VALUE docker compose up -d 失败
      - 执行 TAG_NAME=TAG_VALUE_OLD docker compose up -d
      - 固定日志格式：时间 回滚 image:TAG_VALUE -> TAG_VALUE_OLD
      - 不额外验证回滚结果，本次更新返回非零退出码
  - 普通模式每次执行只产生一行结果日志（异常、回滚时使用上述格式），其余固定格式：时间 成功|失败 image:TAG_VALUE_OLD -> TAG_VALUE，输出到终端同时保存到日志文件
  - -t 只测试 docker pull image:TAG_VALUE 不写日志文件

