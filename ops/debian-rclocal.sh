#!/bin/bash
# Debian 启用 rc.local
# Debian systemd：创建或保留 /etc/rc.local，启用开机执行并立即启动。

set -euo pipefail

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die '请以 root 执行'
command -v systemctl >/dev/null 2>&1 || die '需要 systemctl'
[[ -d /run/systemd/system ]] || die '需要运行中的 systemd 系统实例'
load_state=$(systemctl show --property=LoadState --value rc-local.service)
[[ $load_state == loaded ]] || die "rc-local.service 不可用：$load_state"

rc_local=/etc/rc.local
[[ ! -L $rc_local ]] || die "$rc_local 不能是符号链接"
if [[ -e $rc_local ]]; then
  [[ -f $rc_local ]] || die "$rc_local 必须是普通文件"
else
  # 不覆盖已有启动命令；noclobber 防止创建时覆盖并发生成的文件。
  (set -o noclobber; cat >"$rc_local" <<'EOF'
#!/bin/sh -e
# 在 exit 0 之前添加启动命令。

exit 0
EOF
  )
fi

chmod u+x "$rc_local"
# Debian 的生成器根据文件执行权限自动加入开机启动，无需 enable。
systemctl daemon-reload
systemctl start rc-local.service
systemctl is-active --quiet rc-local.service
printf '%s\n' 'rc-local.service 已启动；/etc/rc.local 将在开机时执行'
