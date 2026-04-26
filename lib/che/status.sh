#!/usr/bin/env bash
# che status — overview of the current repo and che-cli configuration.
# Shows: platform, active provider/model/reachability, git status, submodules,
# recent commits.
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/platform.sh"
. "$LIB_DIR/provider.sh"
provider_load 2>/dev/null || true

if [ -t 1 ]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
  C_RESET=$'\033[0m'
else
  C_BOLD=""; C_DIM=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_RESET=""
fi

case "${1:-}" in
  -h|--help)
    cat <<EOF
che status — overview of the current repo and che-cli configuration.

Usage: che status [options]

Options:
  -s, --short   only the one-line summary (no recent commits, no submodules)
  -h, --help    show this help
EOF
    exit 0
    ;;
esac

short=false
case "${1:-}" in
  -s|--short) short=true ;;
esac

section() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }
kv()      { printf '  %s%-18s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"; }

# --- che-cli ----------------------------------------------------------------
section "che-cli"
kv "platform"   "$CHE_OS"
kv "provider"   "$(provider_active) ${C_DIM}(model: $(provider_active_model))${C_RESET}"

if provider_ping >/dev/null 2>&1; then
  kv "reachable"  "${C_GREEN}yes${C_RESET}"
else
  kv "reachable"  "${C_RED}no${C_RESET} ${C_DIM}— run 'che doctor provider'${C_RESET}"
fi

env_set=()
for v in CHE_PROVIDER CHE_OLLAMA_HOST CHE_OLLAMA_MODEL \
         CHE_OPENAI_HOST CHE_OPENAI_MODEL \
         CHE_ANTHROPIC_HOST CHE_ANTHROPIC_MODEL \
         CHE_MAX_DIFF_CHARS; do
  if [ -n "${!v:-}" ]; then
    env_set+=("$v=${!v}")
  fi
done
if [ "${#env_set[@]}" -gt 0 ]; then
  kv "env" "${env_set[0]}"
  for e in "${env_set[@]:1}"; do
    printf '  %-18s %s\n' "" "$e"
  done
fi

# --- git --------------------------------------------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  section "git"
  printf '  %s(not a git repository)%s\n\n' "$C_DIM" "$C_RESET"
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel)"
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "$(git rev-parse --short HEAD) (detached)")"

upstream=""
ahead_behind=""
if upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
  ab="$(git rev-list --left-right --count "@{u}...HEAD" 2>/dev/null || echo "0	0")"
  behind="$(printf '%s' "$ab" | awk '{print $1}')"
  ahead="$(printf '%s' "$ab" | awk '{print $2}')"
  ahead_behind="${C_DIM}↑${C_RESET}${ahead} ${C_DIM}↓${C_RESET}${behind}"
fi

porcelain="$(git status --porcelain=v1 2>/dev/null)"
if [ -z "$porcelain" ]; then
  dirty="${C_GREEN}clean${C_RESET}"
  staged=0; unstaged=0; untracked=0
else
  staged="$(printf '%s\n' "$porcelain"   | awk '/^[MADRC]/  {n++} END{print n+0}')"
  unstaged="$(printf '%s\n' "$porcelain" | awk '/^.[MADRC]/ {n++} END{print n+0}')"
  untracked="$(printf '%s\n' "$porcelain" | awk '/^\?\?/    {n++} END{print n+0}')"
  dirty="${C_YELLOW}dirty${C_RESET}"
fi

section "git"
kv "repo"     "$(basename "$repo_root")"
kv "branch"   "${C_CYAN}${branch}${C_RESET}"
[ -n "$upstream" ] && kv "upstream" "$upstream  $ahead_behind"
kv "state"    "$dirty"
if [ -n "$porcelain" ]; then
  kv "changes"  "${staged} staged · ${unstaged} unstaged · ${untracked} untracked"
fi

if [ -n "$porcelain" ] && ! $short; then
  printf '\n'
  git -c color.status=always status --short
fi

# --- submodules -------------------------------------------------------------
if [ -f "$repo_root/.gitmodules" ] && ! $short; then
  section "submodules"
  sm_status="$(git -C "$repo_root" submodule status --recursive 2>/dev/null || true)"
  if [ -z "$sm_status" ]; then
    printf '  %s(none initialized)%s\n' "$C_DIM" "$C_RESET"
  else
    printf '%s\n' "$sm_status" | while IFS= read -r line; do
      flag="${line:0:1}"
      rest="${line:1}"
      case "$flag" in
        " ") printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$rest" ;;
        "+") printf '  %s±%s %s %s(out of sync)%s\n' "$C_YELLOW" "$C_RESET" "$rest" "$C_DIM" "$C_RESET" ;;
        "-") printf '  %s−%s %s %s(not initialized)%s\n' "$C_RED" "$C_RESET" "$rest" "$C_DIM" "$C_RESET" ;;
        "U") printf '  %s!%s %s %s(merge conflict)%s\n' "$C_RED" "$C_RESET" "$rest" "$C_DIM" "$C_RESET" ;;
        *)   printf '  %s\n' "$line" ;;
      esac
    done
  fi
fi

# --- recent commits ---------------------------------------------------------
if ! $short; then
  section "recent commits"
  git -c color.ui=always log -n 5 --pretty=format:'  %C(auto)%h%Creset %s %C(dim)(%cr)%Creset' 2>/dev/null
  printf '\n'
fi

printf '\n'
