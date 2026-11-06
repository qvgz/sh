```bash
sudo bash ops/centos-optimize.sh docker   # Docker 云主机
sudo bash ops/centos-optimize.sh k8s      # 云主机 K8s 节点
```

- 仅支持 root 执行的 CentOS/Alma/Rocky 9/10；依赖 dnf、systemctl、modprobe、sysctl、sshd、timedatectl、swapon/swapoff、getenforce/setenforce。维护窗口执行并保留控制台访问。
- 共有配置无开关，会关闭 firewalld、SELinux 转 permissive、关闭 swap、改时区。不安装容器运行时，Docker 用 [containers/docker-install.sh](../containers/docker-install.sh)。
- 失败停止，已完成步骤不自动回退。备份目录打印到终端：原文件按原路径保存，新增文件列于 created.list，另含 sysctl、swap、SELinux、firewalld、tuned、时区原状态。
- 切换场景会移除另一场景的模块与 sysctl 文件，已生效的运行时值重启后恢复。

功能需求：
- 参数必须且只能是 docker 或 k8s；可重复执行，配置无变化不写入，不重启 journald、不 daemon-reexec、不重载 sshd；sysctl、模块每次加载。
- 共有：
  - 安装并启用 tuned、chrony，tuned 使用 `tuned-adm recommend` 推荐的 profile。
  - journald 持久存储，磁盘上限 1G、运行时上限 256M。
  - systemd 与 PAM 默认 nofile=1048576。
  - SELinux 立即转 permissive 并写入 SELINUX=permissive，原为 disabled 时提示重新打标签；firewalld 停止并禁用，未安装则跳过。
  - SSH 写入 sshd_config.d/10-el-container-cloud.conf，关闭 KbdInteractiveAuthentication、GSSAPIAuthentication、UseDNS；sshd -T 核对生效值，不符则失败。
  - 注释 fstab 中 swap 行并 swapoff -a，仍有 swap 则失败；时区 Asia/Shanghai。
  - 加载 overlay；sysctl：IPv4 转发，inotify 实例 8192、watch 1048576，max_map_count=1048576，somaxconn、tcp_max_syn_backlog=65535，本地端口 32768-65535，IPv4/IPv6 邻居表 gc_thresh 8192/32768/65536。
- docker：加载 nf_conntrack；关闭 IPv4/IPv6 接收重定向、IPv4 发送重定向，rp_filter=2；conntrack_max=1048576、buckets=262144。
- k8s：加载 br_netfilter；bridge-nf-call-iptables/ip6tables=1；rp_filter、conntrack 交由 CNI 与 kube-proxy。
- 末尾输出核验信息，观测命令失败不影响退出状态。
