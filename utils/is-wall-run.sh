#!/usr/bin/env bash
# Google generate_204 探测失败时执行命令

is-wall-run() {
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: 'curl' command not found." >&2
    return 3
  fi

  local status
  if status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 3 --max-time 5 \
    'https://www.google.com/generate_204') && [[ "$status" == 204 ]]; then
    return 0
  fi

  local rc=1
  local cmd
  for cmd in "$@"; do
    if ! bash -lc "$cmd"; then
      rc=2
    fi
  done
  return "$rc"
}

is-wall-run "$@"
