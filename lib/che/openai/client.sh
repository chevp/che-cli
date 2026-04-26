#!/usr/bin/env bash
# OpenAI HTTP client wrapper.
# Mirrors the request shape in client/http/openai.http.
# Requires: curl, python3 (or python), OPENAI_API_KEY in env.

_CHE_OPENAI_CLIENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$_CHE_OPENAI_CLIENT_DIR/json.sh"

: "${OPENAI_API_KEY:=}"
: "${CHE_OPENAI_HOST:=https://api.openai.com/v1}"
: "${CHE_OPENAI_MODEL:=gpt-4o-mini}"

openai_configured() { [ -n "$OPENAI_API_KEY" ]; }

openai_ping() {
  openai_configured || return 1
  curl -sS --fail --connect-timeout 5 \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    "$CHE_OPENAI_HOST/models" >/dev/null 2>&1
}

openai_has_model() {
  local model="${1:-$CHE_OPENAI_MODEL}"
  openai_configured || return 1
  curl -sS --fail --connect-timeout 5 \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    "$CHE_OPENAI_HOST/models/$model" >/dev/null 2>&1
}

# openai_generate <prompt> [model]
openai_generate() {
  local prompt="$1"
  local model="${2:-$CHE_OPENAI_MODEL}"
  openai_configured || { echo "OPENAI_API_KEY not set" >&2; return 1; }
  local payload
  payload="{\"model\":$(json_string_literal "$model"),\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":$(json_string_literal "$prompt")}]}"
  curl -sS --fail -X POST "$CHE_OPENAI_HOST/chat/completions" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    | json_extract '.choices[0].message.content'
}
