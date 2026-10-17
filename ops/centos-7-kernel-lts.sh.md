```bash
sudo bash ops/centos-7-kernel-lts.sh
sudo env ELREPO_RELEASE_URL=https://example.com/elrepo-release.rpm bash ops/centos-7-kernel-lts.sh
```

- 仅支持 root 执行的 CentOS 7；依赖 yum、rpm、grubby、sort 及有效仓库、引导盘空间。旧系统仓库可用性需自行核实。
- 仓库及引导配置、旧默认内核备份到打印目录；失败不自动回退。重启前确认控制台救援可用，按输出的 grubby --set-default 命令恢复旧默认内核。

功能需求：
- 无参数安装；ELREPO_RELEASE_URL 可覆盖默认 EL7 release RPM 地址，须使用 HTTPS。
- 安装 ELRepo release RPM，导入其 GPG 密钥，安装 kernel-lt、kernel-lt-devel。
- 按版本排序选择最高已安装 kernel-lt，确认内核文件及 grubby 条目存在后设为默认并核验。
- 保留旧内核，不自动重启。
