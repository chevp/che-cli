#!/usr/bin/env bash
# Verifies OpenAI is reachable and the configured model exists.

CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CHECK_DIR/platform.sh"
. "$CHECK_DIR/openai/client.sh"

type ok   >/dev/null 2>&1 || ok()   { printf "  ✓ %s\n" "$1"; }
type fail >/dev/null 2>&1 || fail() { printf "  ✗ %s\n" "$1"; }
type info >/dev/null 2>&1 || info() { printf "    %s\n" "$1"; }

openai_check() {
  local rc=0

  if openai_configured; then
    ok "OPENAI_API_KEY is set"
  else
    fail "OPENAI_API_KEY not set"
    info "set it via .env (see .env.example) or export it"
    return 1
  fi

  if openai_ping; then
    ok "OpenAI reachable at $CHE_OPENAI_HOST"
  else
    fail "OpenAI unreachable at $CHE_OPENAI_HOST"
    info "verify network and the API key is valid"
    return 1
  fi

  if openai_has_model "$CHE_OPENAI_MODEL"; then
    ok "model available: $CHE_OPENAI_MODEL"
  else
    fail "model not accessible: $CHE_OPENAI_MODEL"
    info "check model name and account access"
    rc=1
  fi
  return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "openai:"
  openai_check
fi
