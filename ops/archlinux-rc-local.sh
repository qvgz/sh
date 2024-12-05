#!/bin/bash
# archlinux 使用 /etc/rc.local
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/archlinux-rc-local.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/archlinux-rc-local.sh)"

set -eux

[[ $(id -u) != '0' ]] && { echo "脚本需要 root 用户执行" ; exit 1 ;}

cat << 'EOF' >> /etc/rc.local
#!/bin/bash

exit 0
EOF

chmod u+x /etc/rc.local

cat << 'EOF' >> /etc/systemd/system/rc-local.service
[Unit]
Description=/etc/rc.local Compatibility
ConditionFileIsExecutable=/etc/rc.local
After=network.target

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=infinity
RemainAfterExit=yes
GuessMainPID=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now rc-local