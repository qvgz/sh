#!/bin/bash
# debian 使用 /etc/rc.local
# 参考：https://u.sb/debian-rc-local/
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/debian-rc-local.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/debian-rc-local.sh)"

set -e

function is_root() {
  if [[ '0' != $(id -u) ]]; then # "$(id -nu)" != "root"
    echo "当前用户不是 root 用户"
    exit 1
  fi
}
is_root

cat <<EOF >/etc/rc.local
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

exit 0
EOF

chmod +x /etc/rc.local
systemctl enable --now rc-local


