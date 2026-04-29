#!/usr/bin/env bash
# Interactive resolver for git warnings (CRLF, ignored files, file-mode, etc.).
#
# Sourced into commit.sh after `git add -A`. When git emits "warning:" or
# "hint:" lines on stderr, we ask the active LLM provider to diagnose the
# warnings and propose a single safe `git config` command. The suggestion is
# offered to the user — never auto-applied without confirmation.
#
# Public entry point:
#   warnings_handle_interactive <stderr_path>
#     0 — handler ran (regardless of whether user accepted the fix)
#     1 — provider unreachable (caller should still proceed; warnings already shown)
#
# Opt out: set CHE_FIX_WARNINGS=0.

WARNINGS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$WARNINGS_LIB_DIR/ui.sh"

if [ -t 1 ]; then
  WARN_C_DIM=$'\033[2m'; WARN_C_BOLD=$'\033[1m'
  WARN_C_GREEN=$'\033[32m'; WARN_C_YELLOW=$'\033[33m'
  WARN_C_RED=$'\033[31m'; WARN_C_CYAN=$'\033[36m'
  WARN_C_RESET=$'\033[0m'
else
  WARN_C_DIM=""; WARN_C_BOLD=""; WARN_C_GREEN=""; WARN_C_YELLOW=""
  WARN_C_RED=""; WARN_C_CYAN=""; WARN_C_RESET=""
fi

# Pull warning/hint lines (and a few lines of trailing context) out of captured
# stderr so we can both display them and feed them to the LLM.
_warnings_collect() {
  local src="$1"
  awk '/^[[:space:]]*(warning|hint):/ { print }' "$src"
}

_warnings_build_prompt() {
  local warnings="$1"
  local platform="${OSTYPE:-unknown}"

  cat <<EOF
You are diagnosing one or more warnings emitted by git for a developer.

Reply with EXACTLY this format and nothing else:

DIAGNOSIS: <one short sentence — what these warnings mean, in plain English>
COMMAND: <a single \`git config\` command that fixes the root cause, or "(none — manual fix)">
WHY: <one short sentence — why that command resolves the warnings>

Rules:
- COMMAND must be a SINGLE line starting with "git config" (local or --global).
  No other commands are allowed. If a config change cannot fix it (e.g. needs
  a .gitattributes file, a rename, or a manual edit), put
  "(none — manual fix)" in COMMAND and explain in WHY what to do instead.
- Be specific to the warnings below; do NOT give generic git advice.
- Prefer repo-local config over --global unless the warning is clearly a
  workstation-wide setting (line endings on Windows, user.email, etc.).
- The current platform is: $platform

Captured warnings:
$warnings
EOF
}

# Pull "COMMAND: <...>" out of the LLM response.
_warnings_extract_command() {
  awk -F': *' '
    /^COMMAND:/ {
      sub(/^COMMAND: */, "")
      print
      exit
    }
  '
}

# Allow only `git config [--local|--global] <key> <value>`. Returns 0 if the
# command is on the allowlist, 1 otherwise. Anything else (rm, push, file
# writes, command substitution, redirection) is rejected.
_warnings_safe_command() {
  local cmd="$1"
  case "$cmd" in
    *\;*|*\|*|*\&*|*\$*|*\`*|*\>*|*\<*) return 1 ;;
  esac
  printf '%s' "$cmd" | grep -qE '^git config(  *--(local|global))?  *[A-Za-z0-9_.-]+  *[^ ].*$'
}

warnings_handle_interactive() {
  local stderr_path="$1"
  [ -s "$stderr_path" ] || return 0

  local warnings
  warnings="$(_warnings_collect "$stderr_path")"
  if [ -z "$warnings" ]; then
    cat "$stderr_path" >&2
    return 0
  fi

  printf '\n%s── git warnings ──%s\n%s\n' \
    "$WARN_C_BOLD" "$WARN_C_RESET" "$warnings" >&2

  if [ "${CHE_FIX_WARNINGS:-1}" = "0" ]; then
    return 0
  fi

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    return 0
  fi

  if ! type provider_smart_generate >/dev/null 2>&1; then
    . "$WARNINGS_LIB_DIR/provider.sh"
    provider_load || return 1
  fi
  provider_ensure_running >/dev/null 2>&1 || true
  if ! provider_ping >/dev/null 2>&1; then
    return 1
  fi

  local prompt out_tmp err_tmp
  prompt="$(_warnings_build_prompt "$warnings")"
  out_tmp="$(mktemp)"
  err_tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$out_tmp' '$err_tmp'" RETURN

  provider_smart_generate "$prompt" >"$out_tmp" 2>"$err_tmp" &
  local gen_pid=$!
  if ! ui_spin "$gen_pid" "asking $(provider_active) to diagnose warnings"; then
    [ -s "$err_tmp" ] && cat "$err_tmp" >&2
    return 1
  fi

  local answer; answer="$(cat "$out_tmp")"
  if [ -z "$answer" ]; then
    return 1
  fi

  local cmd
  cmd="$(printf '%s\n' "$answer" | _warnings_extract_command | tr -d '\r')"
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  cmd="${cmd%"${cmd##*[![:space:]]}"}"

  printf '\n%s%s%s\n' "$WARN_C_CYAN" "$answer" "$WARN_C_RESET"

  if [ -z "$cmd" ] || [ "$cmd" = "(none — manual fix)" ]; then
    printf '\n%sche commit: no automatic fix — see WHY above for manual steps%s\n' \
      "$WARN_C_DIM" "$WARN_C_RESET" >&2
    return 0
  fi

  if ! _warnings_safe_command "$cmd"; then
    printf '\n%sche commit: suggested command is not on the allowlist (only "git config ..." is auto-applied) — apply manually if you want it%s\n' \
      "$WARN_C_YELLOW" "$WARN_C_RESET" >&2
    return 0
  fi

  printf '\napply %s%s%s? [y/N] ' "$WARN_C_BOLD" "$cmd" "$WARN_C_RESET"
  local answer_yn
  if ! read -r answer_yn </dev/tty; then
    printf '\n%sche commit: no tty — skipping fix%s\n' \
      "$WARN_C_DIM" "$WARN_C_RESET" >&2
    return 0
  fi

  case "$answer_yn" in
    y|Y|yes|YES)
      if eval "$cmd"; then
        printf '%s✓ applied: %s%s\n' "$WARN_C_GREEN" "$cmd" "$WARN_C_RESET"
      else
        printf '%sche commit: command failed: %s%s\n' \
          "$WARN_C_RED" "$cmd" "$WARN_C_RESET" >&2
      fi
      ;;
    *)
      printf '%s↷ skipped%s\n' "$WARN_C_DIM" "$WARN_C_RESET"
      ;;
  esac
  return 0
}
