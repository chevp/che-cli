#!/usr/bin/env bash
# che init — provision the local ollama setup so other che commands work.
# - Verifies ollama is installed (prints install instructions if not)
# - Starts `ollama serve` in the background if the server isn't reachable
# - Pulls $CHE_OLLAMA_MODEL if it isn't already present
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/platform.sh"
. "$LIB_DIR/ollama/client.sh"

if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_DIM=""; C_RESET=""
fi
ok()   { printf "  ${C_GREEN}✓${C_RESET} %s\n" "$1"; }
fail() { printf "  ${C_RED}✗${C_RESET} %s\n" "$1"; }
info() { printf "    ${C_DIM}%s${C_RESET}\n" "$1"; }

case "${1:-}" in
  -h|--help)
    cat <<EOF
che init — provision the local ollama setup.

Usage: che init [options]

What it does:
  1. checks the ollama binary is installed
  2. starts 'ollama serve' in the background if not already running
  3. pulls \$CHE_OLLAMA_MODEL if not already present

Options:
  -h, --help    show this help

Environment:
  CHE_OLLAMA_HOST   ollama server (default: http://localhost:11434)
  CHE_OLLAMA_MODEL  model to pull (default: llama3.2)
EOF
    exit 0
    ;;
esac

printf 'che init — ollama (model: %s)\n\n' "$CHE_OLLAMA_MODEL"

# 1. binary
if ! command -v ollama >/dev/null 2>&1; then
  fail "ollama binary not found"
  case "$CHE_OS" in
    darwin)    info "install: brew install ollama" ;;
    windows)   info "install: https://ollama.com/download/windows" ;;
    wsl|linux) info "install: curl -fsSL https://ollama.com/install.sh | sh" ;;
    *)         info "install: https://ollama.com/download" ;;
  esac
  info "re-run 'che init' once installed"
  exit 1
fi
ok "ollama binary found"

# 2. server
if ollama_ping; then
  ok "server reachable at $CHE_OLLAMA_HOST"
else
  info "starting 'ollama serve' in the background…"
  if ollama_serve_start 10; then
    ok "server started at $CHE_OLLAMA_HOST"
  else
    fail "could not reach $CHE_OLLAMA_HOST after starting 'ollama serve'"
    info "start it manually in another terminal: ollama serve"
    exit 1
  fi
fi

# 3. model
if ollama_has_model "$CHE_OLLAMA_MODEL"; then
  ok "model already pulled: $CHE_OLLAMA_MODEL"
else
  info "pulling $CHE_OLLAMA_MODEL (this may take a while)…"
  if ollama pull "$CHE_OLLAMA_MODEL"; then
    ok "model pulled: $CHE_OLLAMA_MODEL"
  else
    fail "ollama pull $CHE_OLLAMA_MODEL failed"
    exit 1
  fi
fi

printf '\nready. try: che doctor ollama\n'
