#!/usr/bin/env bash
# Verifies Anthropic is reachable and the configured model exists.

CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CHECK_DIR/platform.sh"
. "$CHECK_DIR/anthropic/client.sh"

type ok   >/dev/null 2>&1 || ok()   { printf "  ✓ %s\n" "$1"; }
type fail >/dev/null 2>&1 || fail() { printf "  ✗ %s\n" "$1"; }
type info >/dev/null 2>&1 || info() { printf "    %s\n" "$1"; }

anthropic_check() {
  local rc=0

  if anthropic_configured; then
    ok "ANTHROPIC_API_KEY is set"
  else
    fail "ANTHROPIC_API_KEY not set"
    info "set it via .env (see .env.example) or export it"
    return 1
  fi

  if anthropic_ping; then
    ok "Anthropic reachable at $CHE_ANTHROPIC_HOST"
  else
    fail "Anthropic unreachable at $CHE_ANTHROPIC_HOST"
    info "verify network and the API key is valid"
    return 1
  fi

  if anthropic_has_model "$CHE_ANTHROPIC_MODEL"; then
    ok "model available: $CHE_ANTHROPIC_MODEL"
  else
    fail "model not accessible: $CHE_ANTHROPIC_MODEL"
    info "check model name and account access"
    rc=1
  fi
  return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "anthropic:"
  anthropic_check
fi
