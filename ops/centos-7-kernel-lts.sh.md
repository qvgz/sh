`sudo bash centos-7-kernel-lts.sh`：仅 CentOS 7，安装 ELRepo `kernel-lt`/`kernel-lt-devel`，用 `grubby` 设置最高已安装 LT 版本为默认；不删除旧内核、不重启。

CentOS 7 已结束维护，默认 EL7 RPM 地址和仓库可能不可用；`ELREPO_RELEASE_URL` 可指定可信的 HTTPS release RPM。需要有效 yum 源、`grubby` 和引导盘空间。

写入前备份仓库/引导配置及旧默认内核。重启前确认控制台救援可用；失败不自动回退，按终端给出的 `grubby --set-default 旧内核` 恢复。
