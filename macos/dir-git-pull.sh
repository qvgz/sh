#!/bin/bash
# 含有 .git 文件夹执行 git pull
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/macos/dir-git-pull.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/macos/dir-git-pull.sh)"

set -e

for e in "$@";do
    echo $e
    for e2 in $(find $e -type d -name '.git' -print0 | xargs -0I {}  dirname {});do
        cd $e2 && git pull
    done
done




