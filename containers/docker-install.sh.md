```bash
sudo bash containers/docker-install.sh
sudo env DOCKER_MIRROR=mirrors.cloud.tencent.com/docker-ce bash containers/docker-install.sh
```

- 需要 root、Linux、systemd；支持 Debian/Ubuntu、CentOS/Alma/Rocky、Arch。安装软件包可能影响现有容器。
- 配置备份到打印的 `/var/tmp/docker-install-backup.*`。回退需恢复原文件并处理新增配置及软件包；已运行 Docker 的配置更新需择机重启。
- 加速源仅用 ping 判断可达，不验证镜像服务；未验证下载 GPG 密钥指纹。

功能需求：
- 无参数安装；--help 输出用法。
- Debian/Ubuntu、CentOS/Alma/Rocky 安装 Docker Engine、CLI、containerd、Buildx 和 Compose 插件。
  - 默认探测 Google generate_204，成功且状态码为 204 使用 download.docker.com，否则使用腾讯云源。
  - DOCKER_MIRROR 可指定仓库主机/路径，不含协议。
- Arch 从发行版仓库安装 docker、docker-compose、jq、iputils。
- 首次创建 daemon.json 时配置 local 日志驱动、20m × 3 日志限额和 live-restore；已有配置保留其他字段。
- 按 registry_mirrors 数组探测主机，追加可达源完整 URL 并去重；默认数组含 https://mirror.ccs.tencentyun.com。
- dockerd --validate 通过后写入配置，enable --now docker，检查服务状态并输出 docker version；失败停止，不自动回退。
