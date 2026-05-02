#!/usr/bin/env bash
# Verifies Claude Code CLI is installed and reachable.

CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CHECK_DIR/platform.sh"
. "$CHECK_DIR/claude-code/client.sh"

type ok   >/dev/null 2>&1 || ok()   { printf "  %s\n" "$1"; }
type fail >/dev/null 2>&1 || fail() { printf "  error: %s\n" "$1"; }
type info >/dev/null 2>&1 || info() { printf "  hint: %s\n" "$1"; }

claude_code_check() {
  if claude_code_ping; then
    local ver
    ver="$(claude --version 2>/dev/null | head -n1 | awk '{print $1}')"
    ok "claude${ver:+ $ver}"
  else
    fail "claude CLI not on PATH"
    info "install: https://docs.claude.com/claude-code"
    return 1
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "claude-code:"
  claude_code_check
fi
