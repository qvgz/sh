```bash
sudo bash ops/debian-rclocal.sh
```

- 需要 root、运行中的 systemd 及已加载的 rc-local.service；开机执行依赖 rc-local 生成器，不保证网络就绪。
- 立即启动可能执行已有启动命令；启动失败保留文件及权限，可用 journalctl -u rc-local.service -b 排查。

功能需求：
- /etc/rc.local 不存在时创建含 #!/bin/sh -e 和 exit 0 的模板；已有普通文件保留内容，拒绝符号链接及其他类型。
- 添加所有者执行权限，daemon-reload 后 start rc-local.service，检查 active；已运行服务不主动重启。
- 不自动回退；仅当原先无所有者执行权限且其他用户也无执行权限时，可用 chmod u-x /etc/rc.local 撤销本次开机启用，已执行命令的影响另行恢复。
