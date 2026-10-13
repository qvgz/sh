`sudo bash watchexec.sh [版本号]`：Linux x86_64 安装 musl 二进制到 `/usr/local/bin/watchexec`；省略版本查 GitHub 最新 release。

依赖 `curl`、支持 xz 的 `tar`、`jq`。下载成功、归档唯一目标及版本检查通过后原子替换；旧版本备份路径会打印，复制回可回退。安装依赖 GitHub HTTPS 信任，未增加签名校验。
