```bash
sudo bash ops/centos-optimize.sh
sudo bash ops/centos-optimize.sh --global-limits --timezone-shanghai
```

- 仅支持 root 执行的 CentOS/Alma/Rocky 9/10；依赖 dnf、systemctl、modprobe、sysctl、sshd。维护窗口执行并保留控制台访问。
- 重启 journald、重载 sshd；失败停止，已完成步骤不自动回退。备份目录打印到终端，恢复需处理原文件、新增文件及运行状态。

功能需求：
- 安装并启用 tuned、chrony，tuned 使用 virtual-guest。
- journald 使用持久存储，磁盘上限 1G、运行时上限 256M。
- 持久加载 overlay、br_netfilter、nf_conntrack；启用 IPv4 转发、TCP syncookies，关闭 IPv4/IPv6 重定向和源路由，IPv4 rp_filter=2。
- SSH 配置关闭 KbdInteractiveAuthentication、GSSAPIAuthentication、UseDNS；校验后重载。
- --global-limits 设置 fs.file-max/fs.nr_open=2097152，systemd 默认 nofile=1048576、nproc=65535、TasksMax=infinity，PAM nofile=1048576、nproc=65535；新会话/服务继承。
- --timezone-shanghai 设置 Asia/Shanghai；--disable-selinux 写入 disabled 并尝试转为 permissive，完全禁用需重启；--disable-firewalld 停止并禁用服务，默认不关闭两者。
- 写入前备份相关文件及 sysctl、firewalld、tuned、时区状态；末尾输出核验信息，部分观测命令失败不影响退出状态。
