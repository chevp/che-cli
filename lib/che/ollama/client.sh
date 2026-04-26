#!/usr/bin/env bash
# Ollama HTTP client wrapper. Sourced by commands that talk to Ollama.
# Requires: curl, jq

: "${CHE_OLLAMA_HOST:=http://localhost:11434}"
: "${CHE_OLLAMA_MODEL:=llama3.2}"

ollama_ping() {
  curl -sS --fail --connect-timeout 2 "$CHE_OLLAMA_HOST/api/tags" >/dev/null 2>&1
}

ollama_has_model() {
  local model="${1:-$CHE_OLLAMA_MODEL}"
  curl -sS --fail --connect-timeout 2 "$CHE_OLLAMA_HOST/api/tags" 2>/dev/null \
    | jq -e --arg m "$model" '.models[]? | select(.name | startswith($m))' >/dev/null
}

# ollama_generate <prompt> [model]
# Echoes the model's response on stdout. Returns non-zero on transport failure.
ollama_generate() {
  local prompt="$1"
  local model="${2:-$CHE_OLLAMA_MODEL}"
  local payload
  payload="$(jq -n --arg model "$model" --arg prompt "$prompt" \
    '{model: $model, prompt: $prompt, stream: false}')"
  curl -sS --fail -X POST "$CHE_OLLAMA_HOST/api/generate" \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    | jq -r '.response // empty'
}
