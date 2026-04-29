#!/usr/bin/env bash
# Verifies GitHub Copilot CLI is installed and reachable.

CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CHECK_DIR/platform.sh"
. "$CHECK_DIR/copilot/client.sh"

type ok   >/dev/null 2>&1 || ok()   { printf "  %s\n" "$1"; }
type fail >/dev/null 2>&1 || fail() { printf "  error: %s\n" "$1"; }
type info >/dev/null 2>&1 || info() { printf "  hint: %s\n" "$1"; }

copilot_check() {
  if copilot_ping; then
    local ver
    ver="$(copilot --version 2>/dev/null | head -n 1)"
    ok "copilot CLI found${ver:+ ($ver)}"
  else
    fail "copilot CLI not on PATH"
    info "install: https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli"
    return 1
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "copilot:"
  copilot_check
fi
