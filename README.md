# Shell 脚本

- [cloud/](cloud/)：第三方云平台相关
- [configs/](configs/)：配置模板
- [configs/](configs/)：容器相关
- [ops/](ops/)：功能脚本一般不复用
- [utils/](utils/)：简短功能脚本能复用
- [tests/](tests/)：测试

首行注释简短描述脚本关键功能，作为脚本的简要说明。仅在需要时补充同名 `.sh.md`，记录参数、依赖、关键副作用和功能需求，行为修改时同步更新。脚本的测试脚本统一放在 tests 目录。

脚本使用 Bash，平台和依赖以脚本及说明为准。运行前查看用途；安装、刷新、清理等脚本会修改目标环境。

## cloud

| 脚本名 | 介绍 |
| :- | :- |
| [wangsu-cdn-refresh.sh](https://qvgz.org/sh/cloud/wangsu-cdn-refresh.sh) | [网宿 CDN 刷新](cloud/wangsu-cdn-refresh.sh.md) |

## containers

| 脚本名 | 介绍 |
| :- | :- |
| [compose-update.sh](https://qvgz.org/sh/containers/compose-update.sh) | Compose 容器更新 |
| [docker-health.sh](https://qvgz.org/sh/containers/docker-health.sh) | [Docker 容器健康检查](containers/docker-health.sh.md) |
| [docker-image-clean.sh](https://qvgz.org/sh/containers/docker-image-clean.sh) | [保留最近 N 个不同镜像](containers/docker-image-clean.sh.md) |
| [docker-install.sh](https://qvgz.org/sh/containers/docker-install.sh) | [安装 Docker Engine](containers/docker-install.sh.md) |

## ops

| 脚本名 | 介绍 |
| :- | :- |
| [analyze-baseline.sh](https://qvgz.org/sh/ops/analyze-baseline.sh) | [分析 CPU、内存、磁盘和网络性能](ops/analyze-baseline.sh.md) |
| [centos-7-kernel-lts.sh](https://qvgz.org/sh/ops/centos-7-kernel-lts.sh) | [CentOS 7 安装 kernel-lt](ops/centos-7-kernel-lts.sh.md) |
| [centos-optimize.sh](https://qvgz.org/sh/ops/centos-optimize.sh) | [EL 9/10 容器主机基线](ops/centos-optimize.sh.md) |
| [debian-rclocal.sh](https://qvgz.org/sh/ops/debian-rclocal.sh) | [Debian 启用 rc.local](ops/debian-rclocal.sh.md) |
| [ip-conn-stat.sh](https://qvgz.org/sh/ops/ip-conn-stat.sh) | [按本地/远端地址统计已建立 TCP IPv4 连接](ops/ip-conn-stat.sh.md) |
| [linux-baseline.sh](https://qvgz.org/sh/ops/linux-baseline.sh) | [采集 CPU、内存、磁盘、网络当前负载](ops/linux-baseline.sh.md) |
| [log-clean.sh](https://qvgz.org/sh/ops/log-clean.sh) | [轮转目录顶层 .log 文件](ops/log-clean.sh.md) |
| [proc-watch-list.sh](https://qvgz.org/sh/ops/proc-watch-list.sh) | [Linux 进程列表守护](ops/proc-watch-list.sh.md) |
| [rdap.sh](https://qvgz.org/sh/ops/rdap.sh) | [WHOIS/RDAP 查询域名注册信息及到期时间](ops/rdap.sh.md) |
| [ssl-check.sh](https://qvgz.org/sh/ops/ssl-check.sh) | [HTTPS/SSL/TLS 证书信息及到期时间](ops/ssl-check.sh.md) |
| [watchdog.sh](https://qvgz.org/sh/ops/watchdog.sh) | 进程守护 |
| [watchexec-install.sh](https://qvgz.org/sh/ops/watchexec-install.sh) | [watchexec 安装](ops/watchexec-install.sh.md) |
| [wechat2.sh](https://qvgz.org/sh/ops/wechat2.sh) | [macOS 微信多开](ops/wechat2.sh.md) |

## utils

| 脚本名 | 介绍 |
| :- | :- |
| [check-ip.sh](https://qvgz.org/sh/utils/check-ip.sh) | 检查 IP 格式 (IPv4) |
| [cleanup-run.sh](https://qvgz.org/sh/utils/cleanup-run.sh) | [退出时清理运行的子进程](utils/cleanup-run.sh.md) |
| [convert-middle-underline.sh](https://qvgz.org/sh/utils/convert-middle-underline.sh) | 转换中划线为下划线 |
| [create-name.sh](https://qvgz.org/sh/utils/create-name.sh) | [生成随机用户名](utils/create-name.sh.md) |
| [create-passwd.sh](https://qvgz.org/sh/utils/create-passwd.sh) | [生成随机密码](utils/create-passwd.sh.md) |
| [get-domain-ip-dig.sh](https://qvgz.org/sh/utils/get-domain-ip-dig.sh) | [输出公网 DNS 记录](utils/get-domain-ip-dig.sh.md) |
| [get-domain-ip-host.sh](https://qvgz.org/sh/utils/get-domain-ip-host.sh) | [输出本机 DNS 记录](utils/get-domain-ip-host.sh.md) |
| [get-export-ip.sh](https://qvgz.org/sh/utils/get-export-ip.sh) | [获取出口公网 IPv4 地址](utils/get-export-ip.sh.md) |
| [get-ip-info.sh](https://qvgz.org/sh/utils/get-ip-info.sh) | [查询 IPv4 地理信息](utils/get-ip-info.sh.md) |
| [is-root.sh](https://qvgz.org/sh/utils/is-root.sh) | 判断是否是 root 用户 |
| [is-wall-run.sh](https://qvgz.org/sh/utils/is-wall-run.sh) | [Google generate_204 探测失败时执行命令](utils/is-wall-run.sh.md) |
| [is-yes.sh](https://qvgz.org/sh/utils/is-yes.sh) | 回车、y、yes 为同意 |
| [unixtime.sh](https://qvgz.org/sh/utils/unixtime.sh) | [时间戳相关](utils/unixtime.sh.md) |
| [wexec.sh](https://qvgz.org/sh/utils/wexec.sh) | 当前目录变更时执行命令 |
