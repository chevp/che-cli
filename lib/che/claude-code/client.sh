#!/usr/bin/env bash
# Claude Code CLI wrapper. Unlike the other providers, this one shells out to
# the `claude` binary instead of speaking HTTP — auth (subscription or API
# key) is handled by claude itself, so che-cli never sees credentials.
# Requires: claude on PATH (https://docs.claude.com/claude-code).

claude_code_ping() {
  command -v claude >/dev/null 2>&1
}

# Claude Code manages its own model selection — there is nothing to verify.
claude_code_has_model() {
  return 0
}

# claude_code_generate <prompt> [model_unused]
# Prompt goes via stdin to avoid ARG_MAX limits on long diffs.
claude_code_generate() {
  local prompt="$1"
  command -v claude >/dev/null 2>&1 || { echo "claude CLI not on PATH" >&2; return 1; }
  printf '%s' "$prompt" | claude -p
}
