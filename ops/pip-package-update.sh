#!/bin/bash
# pip 包更新
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/pip-package-update.sh)"
# bash -c "$(curl -fsSL https://proxy.qvgz.org/sh/ops/pip-package-update.sh)"

set -e

old_list=$(pip list --outdated --format=freeze | awk -F "==" '{print $1}')

for e in $old_list ; do
  pip install -U $e
done
