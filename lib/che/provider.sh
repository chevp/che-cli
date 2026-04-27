#!/usr/bin/env bash
# Provider router. Sources the active provider's client.sh and exposes a
# uniform interface (provider_ping, provider_generate, provider_has_model).
# The active provider is selected via CHE_PROVIDER (default: ollama).

CHE_PROVIDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

provider_active() {
  printf '%s' "${CHE_PROVIDER:-ollama}"
}

# Function names can't contain '-', so map the provider key to its prefix
# (e.g. "claude-code" → "claude_code").
_provider_fn_prefix() {
  local p; p="$(provider_active)"
  printf '%s' "${p//-/_}"
}

provider_load() {
  local p
  p="$(provider_active)"
  case "$p" in
    ollama|claude-code)
      . "$CHE_PROVIDER_DIR/$p/client.sh"
      ;;
    *)
      echo "che: unknown provider '$p' (valid: ollama, claude-code)" >&2
      return 1
      ;;
  esac
}

provider_ping() {
  "$(_provider_fn_prefix)_ping"
}

# Best-effort: ensure the active provider's server is running locally.
# For ollama, spawns `ollama serve` in the background if not already up.
# For the claude-code subprocess there is nothing to start.
# Returns 0 if the provider is reachable after the attempt, 1 otherwise.
provider_ensure_running() {
  local p; p="$(provider_active)"
  case "$p" in
    ollama) ollama_serve_start ;;
    *)      provider_ping ;;
  esac
}

provider_has_model() {
  "$(_provider_fn_prefix)_has_model" "$@"
}

provider_generate() {
  "$(_provider_fn_prefix)_generate" "$@"
}

provider_active_model() {
  local p; p="$(provider_active)"
  case "$p" in
    ollama)      printf '%s' "${CHE_OLLAMA_MODEL:-llama3.2}" ;;
    claude-code) printf '%s' "claude-code (CLI-managed)" ;;
  esac
}

# Lazy-load the claude-code client without changing CHE_PROVIDER, so simple
# tasks can escalate to it on demand.
_provider_load_claude_code() {
  type claude_code_generate >/dev/null 2>&1 && return 0
  [ -f "$CHE_PROVIDER_DIR/claude-code/client.sh" ] || return 1
  . "$CHE_PROVIDER_DIR/claude-code/client.sh"
}

# provider_smart_generate <prompt> [--complex]
# Routes simple tasks through the active provider (default: ollama) and
# escalates to the claude-code CLI when:
#   - --complex was passed by the caller, OR
#   - CHE_FORCE_CLAUDE_CODE=1 is set in the environment, OR
#   - the active provider is unreachable (auto-fallback).
# Falls through to the active provider if claude-code is requested but the
# `claude` binary is not installed, so a missing escalation target never
# breaks the simple path.
provider_smart_generate() {
  local prompt="" complex=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --complex) complex=true; shift ;;
      *)         prompt="$1"; shift ;;
    esac
  done

  local force_claude=false
  if $complex || [ "${CHE_FORCE_CLAUDE_CODE:-0}" = "1" ]; then
    force_claude=true
  fi

  if $force_claude; then
    if _provider_load_claude_code && claude_code_ping; then
      claude_code_generate "$prompt"
      return $?
    fi
    echo "che: claude CLI not available — falling back to '$(provider_active)'" >&2
  fi

  if provider_ping; then
    provider_generate "$prompt"
    return $?
  fi

  if _provider_load_claude_code && claude_code_ping; then
    echo "che: provider '$(provider_active)' unreachable — escalating to claude-code" >&2
    claude_code_generate "$prompt"
    return $?
  fi

  echo "che: no LLM provider available (active='$(provider_active)', claude CLI missing)" >&2
  return 1
}
