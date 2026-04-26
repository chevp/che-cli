#!/usr/bin/env bash
# Ollama HTTP client wrapper. Sourced by commands that talk to Ollama.
# Requires: curl, python3 (or python).

_CHE_OLLAMA_CLIENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$_CHE_OLLAMA_CLIENT_DIR/json.sh"

: "${CHE_OLLAMA_HOST:=http://localhost:11434}"
: "${CHE_OLLAMA_MODEL:=llama3.2}"

ollama_ping() {
  curl -sS --fail --connect-timeout 2 "$CHE_OLLAMA_HOST/api/tags" >/dev/null 2>&1
}

ollama_has_model() {
  local model="${1:-$CHE_OLLAMA_MODEL}"
  curl -sS --fail --connect-timeout 2 "$CHE_OLLAMA_HOST/api/tags" 2>/dev/null \
    | CHE_JSON_PREFIX="$model" _che_json_python -c 'import json,os,sys
data=json.load(sys.stdin)
prefix=os.environ["CHE_JSON_PREFIX"]
sys.exit(0 if any((m.get("name") or "").startswith(prefix) for m in data.get("models") or []) else 1)'
}

# ollama_generate <prompt> [model]
# Echoes the model's response on stdout. Returns non-zero on transport failure.
ollama_generate() {
  local prompt="$1"
  local model="${2:-$CHE_OLLAMA_MODEL}"
  local payload
  payload="{\"model\":$(json_string_literal "$model"),\"prompt\":$(json_string_literal "$prompt"),\"stream\":false}"
  curl -sS --fail -X POST "$CHE_OLLAMA_HOST/api/generate" \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    | json_extract '.response'
}
