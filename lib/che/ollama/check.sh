#!/usr/bin/env bash
# Verifies Ollama is installed, the server is reachable, and the model is pulled.
# Defines: ollama_check (returns 0 on full success, 1 otherwise)
# Prints status lines via the ok/fail/info helpers if defined by the caller.

CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CHECK_DIR/platform.sh"
. "$CHECK_DIR/ollama/client.sh"

# Fallback formatters if doctor.sh hasn't loaded its own.
type ok   >/dev/null 2>&1 || ok()   { printf "  %s\n" "$1"; }
type fail >/dev/null 2>&1 || fail() { printf "  error: %s\n" "$1"; }
type info >/dev/null 2>&1 || info() { printf "  hint: %s\n" "$1"; }

ollama_install_hint() {
  case "$CHE_OS" in
    darwin)    info "install: brew install ollama" ;;
    windows)   info "install: https://ollama.com/download/windows" ;;
    wsl|linux) info "install: curl -fsSL https://ollama.com/install.sh | sh" ;;
    *)         info "install: https://ollama.com/download" ;;
  esac
  info "guide:   https://chevp.github.io/cura-llm-local/  (5-min local setup)"
}

ollama_check() {
  local rc=0 ver=""
  local host="${CHE_OLLAMA_HOST#*://}"

  if command -v ollama >/dev/null 2>&1; then
    ver="$(ollama --version 2>/dev/null | head -n1 | awk '{print $NF}')"
  else
    fail "ollama binary not found"
    ollama_install_hint
    rc=1
  fi

  if ollama_ping; then
    ok "ollama${ver:+ $ver} · server@${host}"
  else
    info "no response at $CHE_OLLAMA_HOST — starting 'ollama serve' in the background…"
    if ollama_serve_start 10; then
      ok "ollama${ver:+ $ver} · server@${host}"
    else
      fail "could not reach $CHE_OLLAMA_HOST after starting 'ollama serve'"
      info "start it manually in another terminal: ollama serve"
      return 1
    fi
  fi

  if ollama_has_model "$CHE_OLLAMA_MODEL"; then
    ok "model:$CHE_OLLAMA_MODEL"
  else
    fail "model not pulled: $CHE_OLLAMA_MODEL"
    info "pull it: che init  (or: ollama pull $CHE_OLLAMA_MODEL)"
    rc=1
  fi

  return "$rc"
}

# Allow direct execution: bash lib/che/ollama/check.sh
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "ollama:"
  ollama_check
fi
