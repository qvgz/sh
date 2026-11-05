```bash
bash ops/zoxide-fzf-install.sh
```

- 以需要配置的用户执行（不要 `sudo bash`，否则配置写入 root）；装包时自动调用 sudo。
- 依赖 GitHub 访问（fzf 仓库、zoxide 官方脚本回退）。
- `~/.bashrc` 有变化时备份为 `~/.bashrc.bak.<时间戳>`，复制回去即可回退。

功能需求：
- 按 `/etc/os-release` 识别 apt（Debian/Ubuntu）或 dnf（EL 系），其他系统退出。
- 缺少 git、curl、tar 时才安装。
- zoxide 已存在且 >= 0.8.0 则跳过；未安装且系统源版本 >= 0.8.0 时装系统包（EL 先装 epel-release），否则用官方脚本装到 `~/.local/bin`（Debian 12 源为 0.4.3）。
- fzf 克隆或更新 `~/.fzf`，`install --bin` 下载最新二进制到 `~/.fzf/bin`。
- `~/.bashrc` 删除旧标记块后在末尾追加：PATH 前置 `~/.local/bin`、`~/.fzf/bin`，交互 shell 加载 `fzf --bash` 与 `zoxide init bash`；内容无变化不改写。
