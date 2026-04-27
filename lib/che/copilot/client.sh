#!/usr/bin/env bash
# GitHub Copilot CLI wrapper. Like claude-code, this provider shells out to a
# CLI binary instead of speaking HTTP — auth (Copilot subscription) is owned
# by `copilot` itself, so che-cli never sees credentials.
# Requires: copilot on PATH (https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli).

copilot_ping() {
  command -v copilot >/dev/null 2>&1
}

# Copilot manages its own model selection — there is nothing to verify.
copilot_has_model() {
  return 0
}

# copilot_generate <prompt> [model_unused]
# Prompt goes via stdin to avoid ARG_MAX limits on long diffs.
copilot_generate() {
  local prompt="$1"
  command -v copilot >/dev/null 2>&1 || { echo "copilot CLI not on PATH" >&2; return 1; }
  printf '%s' "$prompt" | copilot -p --allow-all-tools 2>/dev/null
}
