#!/usr/bin/env bash
# Tiny UI helpers. Currently: a braille spinner shown while a background
# process is running. Writes to stderr so stdout stays capture-friendly,
# and silently no-ops when stderr is not a TTY (CI, pipes, redirects).

ui_spin() {
  local pid="$1" msg="${2:-working}"

  if [ ! -t 2 ]; then
    wait "$pid"
    return $?
  fi

  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local i=0

  # Hide cursor; restore on any exit path so a Ctrl+C doesn't leave it hidden.
  printf '\033[?25l' >&2
  trap 'printf "\r\033[K\033[?25h" >&2' EXIT INT TERM

  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[36m%s\033[0m %s' "${frames[$((i % 10))]}" "$msg" >&2
    i=$((i + 1))
    sleep 0.08
  done

  wait "$pid"
  local rc=$?

  printf '\r\033[K\033[?25h' >&2
  trap - EXIT INT TERM
  return $rc
}
