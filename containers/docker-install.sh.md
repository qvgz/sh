`sudo bash containers/docker-install.sh`：安装 Docker Engine、Compose/Buildx（Arch 使用发行版 Docker/Compose），支持 Debian/Ubuntu、CentOS/Alma/Rocky、Arch 的 systemd 主机。

默认使用 `download.docker.com`；Google `https://www.google.com/generate_204` 探测失败或未返回 204 时改用 `mirrors.cloud.tencent.com/docker-ce`。`DOCKER_MIRROR` 可显式覆盖安装源（主机/路径）；Arch 使用发行版仓库。

`registry_mirrors` 数组维护加速源，默认包含 `https://mirror.ccs.tencentyun.com`。依次 ping URL 的主机名，将可达源的完整 URL（含路径）追加到 `registry-mirrors`，去重并保留已有项。首次生成 local 日志限额、live-restore 配置；已有配置的其他字段保留，并用 [dockerd --validate](https://docs.docker.com/reference/cli/dockerd/) 检查。

已运行的 Docker 需择机重启以应用加速配置。配置备份位置打印到终端；按原路径恢复后验证并重启 Docker。软件包安装可能影响现有容器，脚本不再改存储驱动、用户组或覆盖资源限制。软件包回退须另行处理。
