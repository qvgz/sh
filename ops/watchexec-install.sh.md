```bash
sudo bash ops/watchexec-install.sh
sudo bash ops/watchexec-install.sh 2.3.0
```

- 仅 Linux x86_64、root；依赖 curl、支持 xz 的 tar、jq。依赖 GitHub HTTPS 信任，未额外校验签名或摘要。
- 已有目标备份路径打印到终端，复制回 /usr/local/bin/watchexec 可回退。

功能需求：
- 接受可选版本号，允许 v 前缀，格式为三段数字；省略时查询 GitHub 最新 release。
- 已有可执行目标版本相同则退出；否则下载对应 x86_64-unknown-linux-musl.tar.xz。
- 确认归档仅有一个名为 watchexec 的目标，提取并执行 --version 校验。
- 备份旧目标后，在 /usr/local/bin 内准备临时文件并原子替换 watchexec，输出安装版本；失败退出并清理临时文件。
