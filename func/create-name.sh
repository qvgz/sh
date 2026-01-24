#!/usr/bin/env bash
# 生成随机用户名
# $1 为指定位数，缺省为 7 位

create_passwd() {
  local length="${1:-7}"

  if ! [[ "$length" =~ ^[0-9]+$ ]]; then
    echo "Error: length must be an integer." >&2
    return 1
  fi
  if (( length < 1 )); then
    echo "Error: Name length must be at least 1." >&2
    return 1
  fi

  # 固定 ASCII 语义，避免 locale 影响
  export LC_ALL=C

  # 字符集（去除易混淆字符: 0, O, 1, l, I）
  local -r digits="23456789"
  local -r lower="abcdefghijkmnpqrstuvwxyz"
  local -r upper="ABCDEFGHJKMNPQRSTUVWXYZ"
  local -r all_chars="${digits}${lower}${upper}"

  # 从 charset 均匀取 1 个字符：拒绝采样，避免取模偏差
  rand_char() {
    local charset="$1"
    local -i clen=${#charset}
    local -i limit=$(( 256 - (256 % clen) ))  # 仅接受 [0, limit-1]
    local b idx
    while :; do
      b=$(od -An -N1 -tu1 < /dev/urandom | tr -d ' ')
      (( b < limit )) || continue
      idx=$(( b % clen ))
      printf '%s' "${charset:idx:1}"
      return 0
    done
  }

  local passwd=""

  # 填充剩余
  for ((i=0; i<length; i++)); do
    passwd+="$(rand_char "$all_chars")"
  done

  # shuffle：显式指定随机源
  # fold/shuf/tr 都在 ASCII 单字节下工作稳定（LC_ALL=C 已设）
  printf '%s' "$passwd" | fold -w1 | shuf --random-source=/dev/urandom | tr -d '\n'
}

create_passwd "${1:-}"
