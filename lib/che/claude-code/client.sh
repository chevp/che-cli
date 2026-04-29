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

_claude_code_is_execution_error() {
  [ "$(printf '%s' "$1" | tr -d '[:space:]')" = "Executionerror" ]
}

# Repair a known recurring corruption of ~/.claude/plugins/installed_plugins.json
# where each entry is wrapped in a single-element array but Claude Code's Zod
# schema expects a plain object. Returns 0 if a repair was made, 1 otherwise.
_claude_code_repair_plugins() {
  local f="${HOME}/.claude/plugins/installed_plugins.json"
  [ -f "$f" ] || return 1
  # Prefer a python that actually runs (Windows ships a python3 stub in
  # WindowsApps that opens the Store instead of executing).
  local py=""
  for cand in python3 python py; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import sys" >/dev/null 2>&1; then
      py="$cand"; break
    fi
  done
  [ -n "$py" ] || return 1
  "$py" - "$f" <<'PY' || return 1
import json, sys, shutil
path = sys.argv[1]
with open(path, encoding='utf-8') as fh:
    data = json.load(fh)
plugins = data.get('plugins') or {}
changed = False
for k, v in list(plugins.items()):
    if isinstance(v, list) and len(v) == 1 and isinstance(v[0], dict):
        plugins[k] = v[0]
        changed = True
if not changed:
    sys.exit(2)
shutil.copyfile(path, path + '.bak')
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2)
PY
}

# claude_code_generate <prompt> [model_unused]
# Prompt goes via stdin to avoid ARG_MAX limits on long diffs.
#
# claude -p has a failure mode where it prints the literal string
# "Execution error" to stdout and exits 0 (e.g. when a plugin config fails
# Zod validation). When that happens we try to auto-repair the most common
# cause (malformed installed_plugins.json) and retry once before giving up.
claude_code_generate() {
  local prompt="$1" out
  command -v claude >/dev/null 2>&1 || { echo "claude CLI not on PATH" >&2; return 1; }
  out="$(printf '%s' "$prompt" | claude -p)"
  if _claude_code_is_execution_error "$out"; then
    if _claude_code_repair_plugins; then
      echo "claude-code: repaired malformed ~/.claude/plugins/installed_plugins.json (backup at .bak), retrying" >&2
      out="$(printf '%s' "$prompt" | claude -p)"
    fi
    if _claude_code_is_execution_error "$out"; then
      echo "claude CLI returned 'Execution error' — run 'claude -p --output-format json \"hi\"' to inspect the underlying error" >&2
      return 1
    fi
  fi
  printf '%s' "$out"
}
