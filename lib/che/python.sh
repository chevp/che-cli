#!/usr/bin/env bash

che_python_resolve() {
  local cand

  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c '' >/dev/null 2>&1; then
      printf '%s\n' "$cand"
      return 0
    fi
  done

  if command -v py >/dev/null 2>&1 && py -3 -c '' >/dev/null 2>&1; then
    printf '%s\n' 'py -3'
    return 0
  fi

  if command -v py >/dev/null 2>&1 && py -c '' >/dev/null 2>&1; then
    printf '%s\n' 'py'
    return 0
  fi

  return 1
}

che_python_run() {
  local py
  py="$(che_python_resolve)" || return 127
  case "$py" in
    'py -3') py -3 "$@" ;;
    py) py "$@" ;;
    *) "$py" "$@" ;;
  esac
}
