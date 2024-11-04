#!/usr/bin/env bash
# pip 更新
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/ops/pip-update.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/ops/pip-update.sh)"

set -e

if ping -c 1 google.com ; then
  pip  install --upgrade pip
else
  pip install -i https://mirrors.cloud.tencent.com/pypi/simple --upgrade pip
  pip config set global.index-url https://mirrors.cloud.tencent.com/pypi/simple
fi

