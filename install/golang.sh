#!/usr/bin/env bash
# golang 安装最新版本
# $1 指定 go 版本号，缺省最新（国内必须指定版本号）
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/qvgz/sh/master/install/golang.sh)"
# bash -c "$(curl -fsSL https://qvgz.org/sh/install/golang.sh)"

set -e

go_version=$1
type=""

download_site='https://go.dev/dl'
golang_version_api='https://go.dev'

if [[ -z $go_version ]];then
  go_version=$(curl -fsSL ${golang_version_api}/VERSION?m=text | head -n1)
fi

# golang 已安装，比较版本号
if which go &> /dev/null;then
  v1=${go_version#*.}
  v2=$(go version | awk '{print $3}')
  v2=${v2#*.}
  # v1 不大于 v2 结果 0，if 0 为真
  if awk -v v1=$v1 -v v2=$v2 'BEGIN{exit v1>v2}' ; then
    echo -e "当前 golang 版本 $v2 为最新\n"
    exit 0
  fi
fi

# 安装或更新
if [[ -z "$type" ]]; then
  case $(uname -s) in
    Linux)
      type=linux ;;
    *)
      echo "不支持 OS: $(uname -s)"
      exit 1 ;;
  esac

  case $(uname -m) in
    x86_64)
      type="${type}-amd64";;
    *)
      echo "不支持 arch: $(uname -m)"
      exit 1 ;;
  esac
fi

go_file_name="${go_version}.${type}.tar.gz"
tmpfile=$(mktemp)


wget ${download_site}/${go_file_name} -O $tmpfile && sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf $tmpfile

rm -f $tmpfile
