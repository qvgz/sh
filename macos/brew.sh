#!/usr/bin/env bash
# 记录维护 brew 应用列表
# 环境变量 $BREW_LIST_PATH 指定 brew-list 路径，缺省 brew.sh 与同目录

set -euo pipefail

# --- 配置与环境探测 ---

BREW_BIN="$(command -v brew || true)"
if [[ -z "$BREW_BIN" ]]; then
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    BREW_BIN="/usr/local/bin/brew"
  else
    echo "Error: brew not found." >&2
    exit 1
  fi
fi

# 清单路径：优先环境变量 -> 脚本同目录（文件执行）-> HOME 兜底
if [[ -n "${BREW_LIST_PATH:-}" ]]; then
  LIST_FILE="$BREW_LIST_PATH"
elif [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
  LIST_FILE="$(dirname "${BASH_SOURCE[0]}")/brew-list"
else
  LIST_FILE="${HOME}/.brew-list"
fi

PIN_FILE="${BREW_PIN_LIST_PATH:-${LIST_FILE}.pin}"

touch "$LIST_FILE"
touch "$PIN_FILE"

# --- 核心逻辑 ---

# 无参数：透传 brew（显示帮助/状态）
if [[ $# -eq 0 ]]; then
  "$BREW_BIN"
  exit 0
fi

cmd="$1"
shift

case "$cmd" in
  install)
    "$BREW_BIN" install "$@"

    for app in "$@"; do
      [[ "$app" == -* ]] && continue
      echo "$app" >> "$LIST_FILE"
    done

    tmp="$(mktemp)"
    sort -u "$LIST_FILE" > "$tmp" && mv "$tmp" "$LIST_FILE"
    ;;

  uninstall|remove)
    "$BREW_BIN" uninstall "$@"

    # 用 awk 做精确“整行匹配删除”，避免 sed 正则注入/转义问题
    for app in "$@"; do
      [[ "$app" == -* ]] && continue
      tmp="$(mktemp)"
      awk -v target="$app" '$0 != target {print $0}' "$LIST_FILE" > "$tmp" && mv "$tmp" "$LIST_FILE"
    done
    ;;

  upgrade)
    # 取所有可更新项（第一列为包名）
    mapfile -t outdated < <("$BREW_BIN" outdated --greedy | awk '{print $1}')

    if [[ ${#outdated[@]} -eq 0 ]]; then
      exit 0
    fi

    if [[ -s "$PIN_FILE" ]]; then
      # 过滤 PIN（固定字符串匹配）
      mapfile -t targets < <(printf "%s\n" "${outdated[@]}" | grep -v -F -f "$PIN_FILE" || true)
    else
      targets=("${outdated[@]}")
    fi

    if [[ ${#targets[@]} -eq 0 ]]; then
      exit 0
    fi

    "$BREW_BIN" upgrade "${targets[@]}"
    ;;

  *)
    "$BREW_BIN" "$cmd" "$@"
    ;;
esac
