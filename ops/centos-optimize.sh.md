`sudo bash centos-optimize.sh [选项]`：CentOS/Alma/Rocky 9/10 容器云主机基线；安装 tuned/chrony，设 virtual-guest，配置持久 journal、容器模块、IPv4 转发/网络参数和 SSH 选项。

- `--global-limits`：全局 nofile/nproc、systemd 任务限制；新会话/服务才继承。
- `--timezone-shanghai`：改为上海时区。
- `--disable-selinux`、`--disable-firewalld`：显式关闭对应防护，默认保留；SELinux 完全禁用需重启。

会重启 journald、重载 sshd；失败停止，已完成步骤不自动回退。配置及运行前状态备份到打印的目录；回退须恢复旧文件、删除本次新增文件，恢复 sysctl/tuned/时区及服务状态。应用前保留控制台访问，维护窗口核验业务网络和 SSH。
