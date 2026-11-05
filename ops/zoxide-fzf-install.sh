#!/usr/bin/env bash
# 安装 zoxide（z / zi 目录跳转）+ fzf（Ctrl+R 历史命令模糊搜索），支持 EL 9/10、Debian 12+/Ubuntu
# 以目标用户执行，配置写入该用户 ~/.bashrc；装包需 root 或 sudo。可重复执行。
set -euo pipefail

if [[ ${1:-} == --help ]]; then
    printf '用法：bash %s（以需要配置的用户执行）\n' "$0"; exit 0
fi
(( $# == 0 )) || exit 2

BASHRC=$HOME/.bashrc
MARK_BEGIN='# >>> zoxide+fzf >>>'
MARK_END='# <<< zoxide+fzf <<<'

log() { printf '\033[32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

as_root() {
    if (( EUID == 0 )); then "$@"
    elif command -v sudo >/dev/null; then sudo "$@"
    else die "需要 root 或 sudo：$*"
    fi
}

[[ -r /etc/os-release ]] || die "缺少 /etc/os-release"
# shellcheck source=/dev/null
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
    *" debian "* | *" ubuntu "*) pm=apt ;;
    *" rhel "* | *" fedora "* | *" centos "*) pm=dnf ;;
    *) die "不支持的系统：${PRETTY_NAME:-${ID:-unknown}}" ;;
esac

apt_updated=0
apt_update() { (( apt_updated )) || { as_root apt-get update -qq; apt_updated=1; }; }
pkg_install() {
    if [[ $pm == apt ]]; then
        apt_update
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null
    else
        as_root dnf install -y -q "$@"
    fi
}

# 1. 依赖：缺什么装什么
deps=()
for c in git curl tar; do command -v "$c" >/dev/null || deps+=("$c"); done
[[ $pm == apt && ! -d /etc/ssl/certs ]] && deps+=(ca-certificates)
if (( ${#deps[@]} )); then
    log "安装依赖：${deps[*]}"
    pkg_install "${deps[@]}"
fi

# 2. zoxide：系统包版本 >= ZOXIDE_MIN 时用系统包（EL 需 EPEL），否则官方脚本装到 ~/.local/bin
ZOXIDE_MIN=0.8.0
ver_ge() { [[ $(printf '%s\n' "$2" "$1" | sort -V | head -n1) == "$2" ]]; }
zoxide_ok() {
    local v
    v=$(zoxide --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
    [[ -n $v ]] && ver_ge "$v" "$ZOXIDE_MIN"
}
export PATH=$HOME/.local/bin:$PATH
if zoxide_ok; then
    log "zoxide 已安装：$(zoxide --version)"
else
    if ! command -v zoxide >/dev/null; then
        if [[ $pm == dnf ]]; then
            rpm -q epel-release >/dev/null 2>&1 || pkg_install epel-release || warn "epel-release 安装失败"
            pkg_install zoxide || true
        else
            apt_update
            cand=$(apt-cache policy zoxide | awk '/Candidate:/ {print $2}')
            if [[ -n $cand && $cand != "(none)" ]] && ver_ge "${cand#*:}" "$ZOXIDE_MIN"; then
                pkg_install zoxide || true
            fi
        fi
        hash -r
    fi
    if zoxide_ok; then
        log "zoxide 已通过 $pm 安装"
    else
        warn "系统 zoxide 缺失或低于 $ZOXIDE_MIN，改用官方安装脚本装到 ~/.local/bin"
        curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
        hash -r
        zoxide_ok || die "zoxide 安装失败"
    fi
fi

# 3. fzf：官方仓库最新版装到 ~/.fzf/bin（发行版包版本旧，不支持 fzf --bash）
if [[ -d $HOME/.fzf/.git ]]; then
    log "更新 ~/.fzf"
    git -C "$HOME/.fzf" pull -q --ff-only
else
    log "克隆 fzf 到 ~/.fzf"
    git clone -q --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
fi
"$HOME/.fzf/install" --bin >/dev/null

# 4. ~/.bashrc：替换标记块并放在末尾，内容无变化不改写
tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT
touch "$BASHRC"
awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0==b{s=1;next} $0==e{s=0;next} !s' "$BASHRC" >"$tmp"
cat >>"$tmp" <<EOF
$MARK_BEGIN
[[ :\$PATH: == *":\$HOME/.local/bin:"* ]] || PATH=\$HOME/.local/bin:\$PATH
[[ :\$PATH: == *":\$HOME/.fzf/bin:"* ]] || PATH=\$HOME/.fzf/bin:\$PATH
export PATH
if [[ \$- == *i* ]]; then
    eval "\$(fzf --bash)"
    command -v zoxide >/dev/null && eval "\$(zoxide init bash)"
fi
$MARK_END
EOF
if cmp -s "$tmp" "$BASHRC"; then
    log "$BASHRC 无变化"
else
    backup=$BASHRC.bak.$(date +%Y%m%d%H%M%S)
    cp -p -- "$BASHRC" "$backup"
    cat "$tmp" >"$BASHRC"
    log "已更新 $BASHRC，备份：$backup"
fi

# 5. 校验
log "zoxide: $(zoxide --version)"
log "fzf:    $("$HOME/.fzf/bin/fzf" --version)"
log "完成。执行 'source ~/.bashrc' 或重新登录生效；z 关键词 跳转，zi 交互选择，Ctrl+R 模糊搜索历史"
