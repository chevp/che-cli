#!/usr/bin/env bash
# Anthropic HTTP client wrapper.
# Mirrors the request shape in client/http/anthropic.http.
# Requires: curl, jq, ANTHROPIC_API_KEY in env.

: "${ANTHROPIC_API_KEY:=}"
: "${CHE_ANTHROPIC_HOST:=https://api.anthropic.com/v1}"
: "${CHE_ANTHROPIC_MODEL:=claude-sonnet-4-6}"
: "${CHE_ANTHROPIC_VERSION:=2023-06-01}"
: "${CHE_ANTHROPIC_MAX_TOKENS:=1024}"

anthropic_configured() { [ -n "$ANTHROPIC_API_KEY" ]; }

anthropic_ping() {
  anthropic_configured || return 1
  curl -sS --fail --connect-timeout 5 \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: $CHE_ANTHROPIC_VERSION" \
    "$CHE_ANTHROPIC_HOST/models" >/dev/null 2>&1
}

anthropic_has_model() {
  local model="${1:-$CHE_ANTHROPIC_MODEL}"
  anthropic_configured || return 1
  curl -sS --fail --connect-timeout 5 \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: $CHE_ANTHROPIC_VERSION" \
    "$CHE_ANTHROPIC_HOST/models/$model" >/dev/null 2>&1
}

# anthropic_generate <prompt> [model]
anthropic_generate() {
  local prompt="$1"
  local model="${2:-$CHE_ANTHROPIC_MODEL}"
  anthropic_configured || { echo "ANTHROPIC_API_KEY not set" >&2; return 1; }
  local payload
  payload="$(jq -n \
    --arg model "$model" \
    --arg prompt "$prompt" \
    --argjson max_tokens "$CHE_ANTHROPIC_MAX_TOKENS" \
    '{model: $model, max_tokens: $max_tokens, stream: false, messages: [{role: "user", content: $prompt}]}')"
  curl -sS --fail -X POST "$CHE_ANTHROPIC_HOST/messages" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: $CHE_ANTHROPIC_VERSION" \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    | jq -r '.content[0].text // empty'
}
