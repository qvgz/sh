#!/usr/bin/env bash
# 安装 zoxide（z / zi 目录跳转）+ fzf（Ctrl+R 历史命令模糊搜索）
# 适用：AlmaLinux 10.x / RHEL 10 系，bash
# 用法：以普通用户执行（dnf 步骤会调用 sudo）：bash install_zoxide_fzf.sh
# 可重复执行：已安装则跳过/更新，~/.bashrc 配置块用标记包裹，不会重复追加
set -euo pipefail

BASHRC="$HOME/.bashrc"
MARK_BEGIN="# >>> zoxide+fzf >>>"
MARK_END="# <<< zoxide+fzf <<<"

log() { echo -e "\033[32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[33m[WARN]\033[0m $*"; }

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

# 1. 依赖
log "安装依赖 git curl epel-release"
$SUDO dnf install -y git curl epel-release

# 2. zoxide：优先 EPEL，没有则用官方脚本（装到 ~/.local/bin）
if command -v zoxide &>/dev/null; then
  log "zoxide 已安装：$(zoxide --version)"
elif $SUDO dnf install -y zoxide; then
  log "zoxide 已通过 dnf 安装"
else
  warn "EPEL 无 zoxide，改用官方安装脚本"
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
fi

# 3. fzf：用官方仓库安装（自带 bash 按键绑定，避免 RPM 包缺少 key-bindings 文件）
if [ -d "$HOME/.fzf/.git" ]; then
  log "更新 ~/.fzf"
  git -C "$HOME/.fzf" pull --ff-only
else
  log "克隆 fzf 到 ~/.fzf"
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
fi
"$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-zsh --no-fish

# 4. 写入 ~/.bashrc（先删除旧的标记块，再追加）
[ -f "$BASHRC" ] && cp -a "$BASHRC" "$BASHRC.bak.$(date +%Y%m%d%H%M%S)"
touch "$BASHRC"
sed -i "/^${MARK_BEGIN}\$/,/^${MARK_END}\$/d" "$BASHRC"
cat >> "$BASHRC" <<EOF
${MARK_BEGIN}
export PATH="\$HOME/.local/bin:\$PATH"
eval "\$(zoxide init bash)"
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
${MARK_END}
EOF

# 5. 校验
export PATH="$HOME/.local/bin:$HOME/.fzf/bin:$PATH"
log "zoxide: $(zoxide --version)"
log "fzf:    $(fzf --version)"
log "完成。执行 'source ~/.bashrc' 或重新登录生效"
log "验证：cd 几个目录后 'z 关键词' 能跳转；'zi' 交互选择；Ctrl+R 出现模糊搜索"
