#!/usr/bin/env bash
# che doctor — verifies dependencies, providers, and external services.
# Usage: che doctor [git|docker|ollama|claude-code|copilot|workflow|provider|all]
#
# Output:
#   - default ("all"): one compact line per category (git, docker, ollama, ...).
#     Failures still print as `error:` / `hint:` lines, in git status style.
#   - sub-target (e.g. `che doctor git`): full per-item output.
#   - CHE_VERBOSE=1 forces full output even for "all".
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/platform.sh"
. "$LIB_DIR/provider.sh"

if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

# Git-style: plain text for ok, `error:`/`hint:` prefixes for problems.
_verbose_ok()   { printf "  %s\n" "$1"; }
_verbose_fail() { printf "  ${C_RED}error:${C_RESET} %s\n" "$1"; }
_verbose_info() { printf "  ${C_DIM}hint:${C_RESET} %s\n" "$1"; }

# Default: compact mode. Sub-targets reset to verbose mode below.
: "${CHE_VERBOSE:=0}"
_compact_buf=""
_compact_cat=""

ok() {
  if [ "$CHE_VERBOSE" = "1" ]; then _verbose_ok "$1"; return; fi
  _compact_buf="$_compact_buf · $1"
}
fail() { _verbose_fail "$1"; }   # always visible
info() { _verbose_info "$1"; }   # always visible

. "$LIB_DIR/git/check.sh"
. "$LIB_DIR/docker/check.sh"
. "$LIB_DIR/ollama/check.sh"
. "$LIB_DIR/claude-code/check.sh"
. "$LIB_DIR/copilot/check.sh"
. "$LIB_DIR/workflow/check.sh"

target="${1:-all}"

_run_verbose() {
  local name="$1"; shift
  printf '%s:\n' "$name"
  "$@" || true
}

_run_compact() {
  local name="$1"; shift
  _compact_cat="$name"
  _compact_buf=""
  "$@" || true
  if [ -n "$_compact_buf" ]; then
    printf "${C_DIM}%-9s${C_RESET}%s\n" "$name" "${_compact_buf# · }"
  fi
}

active_provider_check() {
  local p; p="$(provider_active)"
  printf 'active provider: %s (model: %s)\n' "$p" "$(provider_active_model)"
  case "$p" in
    ollama)      ollama_check ;;
    claude-code) claude_code_check ;;
    copilot)     copilot_check ;;
  esac
}

case "$target" in
  git|docker|ollama|claude-code|copilot|workflow|provider)
    # Sub-target: switch to verbose helpers.
    ok()   { _verbose_ok "$1"; }
    fail() { _verbose_fail "$1"; }
    info() { _verbose_info "$1"; }
    case "$target" in
      git)         _run_verbose git         git_check ;;
      docker)      _run_verbose docker      docker_check ;;
      ollama)      _run_verbose ollama      ollama_check ;;
      claude-code) _run_verbose claude-code claude_code_check ;;
      copilot)     _run_verbose copilot     copilot_check ;;
      workflow)    _run_verbose workflow    workflow_check ;;
      provider)    _run_verbose provider    active_provider_check ;;
    esac
    ;;
  all|"")
    if [ "$CHE_VERBOSE" = "1" ]; then
      ok()   { _verbose_ok "$1"; }
      fail() { _verbose_fail "$1"; }
      info() { _verbose_info "$1"; }
      printf 'platform: %s\n' "$CHE_OS"
      printf 'active provider: %s (model: %s)\n\n' \
        "$(provider_active)" "$(provider_active_model)"
      _run_verbose git         git_check
      _run_verbose docker      docker_check
      _run_verbose ollama      ollama_check
      _run_verbose claude-code claude_code_check
      _run_verbose copilot     copilot_check
      _run_verbose workflow    workflow_check
      printf 'shell deps:\n'
      for bin in curl bash; do
        command -v "$bin" >/dev/null 2>&1 && _verbose_ok "$bin" || _verbose_fail "$bin missing"
      done
      command -v python3 >/dev/null 2>&1 && _verbose_ok "python3"
    else
      _run_compact git         git_check
      _run_compact docker      docker_check
      _run_compact ollama      ollama_check
      _run_compact claude      claude_code_check
      _run_compact copilot     copilot_check
      _run_compact workflow    workflow_check
      printf "${C_DIM}provider ${C_RESET}${C_BOLD}%s${C_RESET} / %s  ${C_DIM}(%s)${C_RESET}\n" \
        "$(provider_active)" "$(provider_active_model)" "$CHE_OS"
    fi
    ;;
  -h|--help)
    cat <<EOF
che doctor — verify dependencies and external services.

Usage: che doctor [target]

Targets:
  all          run all checks (default — one compact line per category)
  git          git installation
  docker       docker installation and daemon
  ollama       ollama binary, server reachability, configured model
  claude-code  Claude Code CLI (\`claude\` binary) — used as escalation target
  copilot      GitHub Copilot CLI (\`copilot\` binary)
  workflow     yq (mikefarah Go variant) for che workflow / che run
  provider     only the currently selected provider (CHE_PROVIDER, default: ollama)

Environment:
  CHE_VERBOSE=1            restore the old per-item output for "all"
  CHE_PROVIDER             ollama (default) | claude-code | copilot
  CHE_OLLAMA_HOST/MODEL    Ollama config
  CHE_FORCE_CLAUDE_CODE=1  always escalate provider_smart_generate to claude-code

Persistent settings: 'che config provider <name>' (saved to ~/.che/config).
EOF
    ;;
  *)
    echo "che doctor: unknown target '$target'" >&2
    echo "valid: all, git, docker, ollama, claude-code, copilot, workflow, provider" >&2
    exit 1
    ;;
esac