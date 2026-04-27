#!/usr/bin/env bash
# che doctor — verifies dependencies, providers, and external services.
# Usage: che doctor [git|docker|ollama|claude-code|copilot|workflow|provider|all]
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/platform.sh"
. "$LIB_DIR/provider.sh"

if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_DIM=""; C_RESET=""
fi
ok()   { printf "  ${C_GREEN}✓${C_RESET} %s\n" "$1"; }
fail() { printf "  ${C_RED}✗${C_RESET} %s\n" "$1"; }
info() { printf "    ${C_DIM}%s${C_RESET}\n" "$1"; }

. "$LIB_DIR/git/check.sh"
. "$LIB_DIR/docker/check.sh"
. "$LIB_DIR/ollama/check.sh"
. "$LIB_DIR/claude-code/check.sh"
. "$LIB_DIR/copilot/check.sh"
. "$LIB_DIR/workflow/check.sh"

target="${1:-all}"

run_section() {
  local name="$1"; shift
  printf '%s:\n' "$name"
  "$@" || true
  printf '\n'
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
  git)         run_section git         git_check ;;
  docker)      run_section docker      docker_check ;;
  ollama)      run_section ollama      ollama_check ;;
  claude-code) run_section claude-code claude_code_check ;;
  copilot)     run_section copilot     copilot_check ;;
  workflow)    run_section workflow    workflow_check ;;
  provider)    run_section "provider"  active_provider_check ;;
  all|"")
    printf 'platform: %s\n' "$CHE_OS"
    printf 'active provider: %s (model: %s)\n\n' "$(provider_active)" "$(provider_active_model)"
    run_section git         git_check
    run_section docker      docker_check
    run_section ollama      ollama_check
    run_section claude-code claude_code_check
    run_section copilot     copilot_check
    run_section workflow    workflow_check
    printf 'shell deps:\n'
    for bin in curl bash; do
      if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin"
      else
        fail "$bin missing"
      fi
    done
    if command -v python3 >/dev/null 2>&1; then
      ok "python3"
    elif command -v python >/dev/null 2>&1; then
      ok "python ($(python -c 'import sys;print(sys.version.split()[0])' 2>/dev/null || echo unknown))"
    else
      fail "python3 missing — install via brew install python3 / apt install python3 / winget install Python.Python.3"
    fi
    ;;
  -h|--help)
    cat <<EOF
che doctor — verify dependencies and external services.

Usage: che doctor [target]

Targets:
  all          run all checks (default)
  git          git installation
  docker       docker installation and daemon
  ollama       ollama binary, server reachability, configured model
  claude-code  Claude Code CLI (\`claude\` binary) — used as escalation target
  copilot      GitHub Copilot CLI (\`copilot\` binary)
  workflow     yq (mikefarah Go variant) for che workflow / che run
  provider     only the currently selected provider (CHE_PROVIDER, default: ollama)

Environment:
  CHE_PROVIDER             ollama (default) | claude-code | copilot
  CHE_OLLAMA_HOST/MODEL    Ollama config
  CHE_FORCE_CLAUDE_CODE=1  always escalate provider_smart_generate to claude-code
EOF
    ;;
  *)
    echo "che doctor: unknown target '$target'" >&2
    echo "valid: all, git, docker, ollama, claude-code, copilot, workflow, provider" >&2
    exit 1
    ;;
esac
