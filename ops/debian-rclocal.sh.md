# Debian rc.local

以 root 在运行 systemd、提供 `rc-local.service` 的 Debian 系统执行：

```sh
sudo bash ops/debian-rclocal.sh
```

- 不存在时创建 `/etc/rc.local`；已有普通文件保留内容，拒绝符号链接和其他类型。
- 添加所有者执行权限、重载 systemd 并立即启动服务；已有启动命令可能执行，已运行的服务不会重启。
- 启动失败时保留文件及权限供排查：`journalctl -u rc-local.service -b`。
- 开机运行依赖 systemd 的 rc-local 生成器，不保证网络就绪。
- 撤销本脚本添加的开机执行权限：`sudo chmod u-x /etc/rc.local`（仅限原先所有者无执行权限，且其他用户也无执行权限）。已执行命令的影响需单独恢复。
