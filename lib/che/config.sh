#!/usr/bin/env bash
# che config — manage persistent CLI settings stored in ~/.che/config.
#
# Format: plain `key=value` lines (one per setting). config_load.sh maps each
# known key to its CHE_* env var on every `che` invocation, so saved values
# behave identically to a shell-exported env var. Explicit env still wins, so
# `CHE_PROVIDER=claude-code che commit` always overrides the saved provider.
set -uo pipefail

CHE_CONFIG_FILE="${CHE_CONFIG_FILE:-$HOME/.che/config}"

# Ordered list — also drives `--help` output and validation.
VALID_KEYS="provider ollama_host ollama_model max_diff_chars force_claude_code"

usage() {
  cat <<EOF
che config — view or change persistent settings.

Usage:
  che config                    list saved settings
  che config <key>              show saved value for <key>
  che config <key> <value>      set <key> (validates known keys)
  che config --unset <key>      remove <key> from saved settings
  che config edit               open the config file in \$EDITOR
  che config path               print the config file path

Keys:
  provider              ollama | claude-code | copilot   (default: ollama)
  ollama_host           Ollama base URL                  (default: http://localhost:11434)
  ollama_model          Ollama model name                (default: llama3.2)
  max_diff_chars        diff truncation length           (default: 8000)
  force_claude_code     1 = always escalate provider_smart_generate to claude-code

Examples:
  che config provider claude-code     # use Claude Code CLI for AI tasks
  che config provider ollama          # back to local Ollama
  che config provider                 # show currently saved provider

Notes:
  Settings are saved to $CHE_CONFIG_FILE.
  Explicit env vars still win, so a one-off
    CHE_PROVIDER=claude-code che commit
  overrides whatever 'che config provider' was set to.
EOF
}

is_valid_key() {
  local k="$1"
  case " $VALID_KEYS " in
    *" $k "*) return 0 ;;
  esac
  return 1
}

validate_value() {
  local key="$1" value="$2"
  case "$key" in
    provider)
      case "$value" in
        ollama|claude-code|copilot) ;;
        *)
          echo "che config: invalid provider '$value' (valid: ollama, claude-code, copilot)" >&2
          return 1
          ;;
      esac
      ;;
    force_claude_code)
      case "$value" in
        0|1) ;;
        *)
          echo "che config: force_claude_code must be 0 or 1" >&2
          return 1
          ;;
      esac
      ;;
    max_diff_chars)
      case "$value" in
        ''|*[!0-9]*)
          echo "che config: max_diff_chars must be a positive integer" >&2
          return 1
          ;;
      esac
      ;;
  esac
  return 0
}

read_value() {
  local key="$1"
  [ -f "$CHE_CONFIG_FILE" ] || return 1
  awk -F= -v K="$key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      k = $1
      sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
      if (k == K) {
        v = substr($0, index($0, "=") + 1)
        sub(/^[[:space:]]+/, "", v)
        print v
        found = 1
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$CHE_CONFIG_FILE"
}

list_all() {
  if [ ! -f "$CHE_CONFIG_FILE" ]; then
    echo "(no settings — config file does not exist: $CHE_CONFIG_FILE)"
    return 0
  fi
  # Print the file but skip blanks and full-line comments. Preserves any
  # user-added comments alongside settings (when they hand-edit via `edit`).
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    { print }
  ' "$CHE_CONFIG_FILE"
}

write_value() {
  local key="$1" value="$2"
  mkdir -p "$(dirname "$CHE_CONFIG_FILE")"
  local tmp; tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  if [ -f "$CHE_CONFIG_FILE" ]; then
    awk -F= -v K="$key" '
      {
        k = $1
        sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
        if (k != K) print
      }
    ' "$CHE_CONFIG_FILE" > "$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$CHE_CONFIG_FILE"
}

unset_key() {
  local key="$1"
  [ -f "$CHE_CONFIG_FILE" ] || return 0
  local tmp; tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  awk -F= -v K="$key" '
    {
      k = $1
      sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
      if (k != K) print
    }
  ' "$CHE_CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CHE_CONFIG_FILE"
}

cmd="${1:-list}"
[ "$#" -gt 0 ] && shift || true

case "$cmd" in
  list)
    list_all
    ;;
  -h|--help|help)
    usage
    ;;
  path)
    echo "$CHE_CONFIG_FILE"
    ;;
  edit)
    mkdir -p "$(dirname "$CHE_CONFIG_FILE")"
    [ -f "$CHE_CONFIG_FILE" ] || : > "$CHE_CONFIG_FILE"
    "${EDITOR:-vi}" "$CHE_CONFIG_FILE"
    ;;
  --unset)
    key="${1:-}"
    [ -z "$key" ] && { echo "che config: --unset requires a key" >&2; exit 1; }
    is_valid_key "$key" || { echo "che config: unknown key '$key' (run 'che config --help')" >&2; exit 1; }
    unset_key "$key"
    echo "unset $key"
    ;;
  *)
    is_valid_key "$cmd" \
      || { echo "che config: unknown key '$cmd' (run 'che config --help')" >&2; exit 1; }
    if [ "$#" -eq 0 ]; then
      # Read mode: print saved value, or note that it's unset (so the default
      # applies — `che status` shows what's actually in effect).
      val="$(read_value "$cmd" 2>/dev/null || true)"
      if [ -n "$val" ]; then
        printf '%s\n' "$val"
      else
        echo "(unset — using default; see 'che status' for active value)"
      fi
    else
      value="$1"
      validate_value "$cmd" "$value" || exit 1
      write_value "$cmd" "$value"
      echo "$cmd=$value"
    fi
    ;;
esac
