#!/usr/bin/env bash
# Provider router. Sources the active provider's client.sh and exposes a
# uniform interface (provider_ping, provider_generate, provider_has_model).
# The active provider is selected via CHE_PROVIDER (default: ollama).

CHE_PROVIDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

provider_active() {
  printf '%s' "${CHE_PROVIDER:-ollama}"
}

provider_load() {
  local p
  p="$(provider_active)"
  case "$p" in
    ollama|openai|anthropic)
      . "$CHE_PROVIDER_DIR/$p/client.sh"
      ;;
    *)
      echo "che: unknown provider '$p' (valid: ollama, openai, anthropic)" >&2
      return 1
      ;;
  esac
}

provider_ping() {
  local p; p="$(provider_active)"
  "${p}_ping"
}

# Best-effort: ensure the active provider's server is running locally.
# For ollama, spawns `ollama serve` in the background if not already up.
# For remote providers (openai, anthropic), there is nothing to start.
# Returns 0 if the provider is reachable after the attempt, 1 otherwise.
provider_ensure_running() {
  local p; p="$(provider_active)"
  case "$p" in
    ollama) ollama_serve_start ;;
    *)      "${p}_ping" ;;
  esac
}

provider_has_model() {
  local p; p="$(provider_active)"
  "${p}_has_model" "$@"
}

provider_generate() {
  local p; p="$(provider_active)"
  "${p}_generate" "$@"
}

provider_active_model() {
  local p; p="$(provider_active)"
  case "$p" in
    ollama)    printf '%s' "${CHE_OLLAMA_MODEL:-llama3.2}" ;;
    openai)    printf '%s' "${CHE_OPENAI_MODEL:-gpt-4o-mini}" ;;
    anthropic) printf '%s' "${CHE_ANTHROPIC_MODEL:-claude-sonnet-4-6}" ;;
  esac
}
