```bash
bash containers/docker-image-clean.sh     # 每个仓库保留 5 个
bash containers/docker-image-clean.sh 10  # 每个仓库保留 10 个
bash containers/docker-image-clean.sh --dry-run 10  # 只列出将删除的旧镜像和悬空镜像
```

- 需要 Docker 访问权限；会删除旧标签并清理全部悬空镜像，不强制删除。执行前确认镜像可重新拉取或构建。
- “最近”指镜像创建时间，不是拉取时间；旧构建新拉取的镜像仍排在后面。

功能需求：
- 可选一个参数为保留数（1-999999999），默认 5；参数错误返回 2。
- --dry-run 与保留数顺序不限；只输出将删除的旧镜像和悬空镜像，不做任何删除，返回 0。
- 按 docker image ls 默认创建时间倒序，每个仓库保留最近 N 个不同镜像 ID；同 ID 多标签只占一个名额。
- 被容器（含已停止）引用的镜像占名额且不删除；查询容器或镜像失败时直接退出，不做删除。
- 跳过 <none> 仓库或标签，删除超额镜像的各标签；继续执行 docker image prune -f。
- 任一删除或清理失败返回非零，且不中断后续删除。
