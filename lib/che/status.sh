#!/usr/bin/env bash
# che status — overview of the current repo and che-cli configuration.
# Shows: platform, active provider/model/reachability, git status, submodules,
# recent commits.
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/platform.sh"
. "$LIB_DIR/provider.sh"
. "$LIB_DIR/frontmatter.sh"
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

# --- GitHub: issues + pull requests -----------------------------------------
# Only in full mode. Calls `gh` in parallel into temp files with a 3s timeout
# each, so a slow network never stalls the status output. If gh is missing,
# unauthenticated, or the repo has no GitHub remote, both sections are
# silently skipped.
if ! $short && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh_timeout="${CHE_GH_TIMEOUT:-3}"
  issues_tmp="$(mktemp)"
  prs_tmp="$(mktemp)"
  trap 'rm -f "$issues_tmp" "$prs_tmp"' EXIT

  # Run both queries in parallel. `gh` exits non-zero (and prints to stderr)
  # if the repo isn't on GitHub — we discard stderr and treat empty output
  # as "no GitHub data to show".
  (
    timeout_cmd=""
    command -v timeout >/dev/null 2>&1 && timeout_cmd="timeout $gh_timeout"
    $timeout_cmd gh issue list --state open --limit 5 \
      --json number,title,labels,assignees,body \
      --jq '.[] | "\(.number)\t\(.title)\t\([.labels[].name]|join(","))\t\([.assignees[].login]|join(","))\t\(.body|@base64)"' \
      >"$issues_tmp" 2>/dev/null
  ) &
  issues_pid=$!

  (
    timeout_cmd=""
    command -v timeout >/dev/null 2>&1 && timeout_cmd="timeout $gh_timeout"
    $timeout_cmd gh pr list --state open --limit 5 \
      --json number,title,isDraft,headRefName,reviewDecision,author \
      --jq '.[] | "\(.number)\t\(.title)\t\(.isDraft)\t\(.headRefName)\t\(.reviewDecision // "")\t\(.author.login)"' \
      >"$prs_tmp" 2>/dev/null
  ) &
  prs_pid=$!

  wait "$issues_pid" 2>/dev/null || true
  wait "$prs_pid"    2>/dev/null || true

  # issues — parse status/progress from frontmatter at the body's head, if any
  section "issues"
  if [ -s "$issues_tmp" ]; then
    while IFS=$'\t' read -r num title labels assignees body_b64; do
      body=""
      if [ -n "$body_b64" ]; then
        body="$(printf '%s' "$body_b64" | base64 -d 2>/dev/null || true)"
      fi
      FM_NAME=""; FM_STATUS=""; FM_PROGRESS=""
      if [ -n "$body" ]; then
        frontmatter_parse_stdin <<<"$body"
      fi
      badge_str="$(frontmatter_status_badge "$FM_STATUS")"

      meta=""
      [ -n "$FM_PROGRESS" ] && meta="${meta} ${C_DIM}(${FM_PROGRESS})${C_RESET}"
      [ -n "$labels" ]      && meta="${meta} ${C_DIM}[${labels}]${C_RESET}"
      [ -n "$assignees" ]   && meta="${meta} ${C_DIM}@${assignees}${C_RESET}"
      printf '  %s#%s%s %-11b %s%s\n' \
        "$C_CYAN" "$num" "$C_RESET" "$badge_str" "$title" "$meta"
    done <"$issues_tmp"
  else
    printf '  %s(none open)%s\n' "$C_DIM" "$C_RESET"
  fi

  # pull requests
  section "pull requests"
  if [ -s "$prs_tmp" ]; then
    while IFS=$'\t' read -r num title is_draft head review author; do
      state_tag=""
      if [ "$is_draft" = "true" ]; then
        state_tag="${C_DIM}draft${C_RESET}"
      else
        case "$review" in
          APPROVED)          state_tag="${C_GREEN}approved${C_RESET}" ;;
          CHANGES_REQUESTED) state_tag="${C_RED}changes-requested${C_RESET}" ;;
          REVIEW_REQUIRED)   state_tag="${C_YELLOW}review-required${C_RESET}" ;;
          "")                state_tag="${C_DIM}open${C_RESET}" ;;
          *)                 state_tag="${C_DIM}${review}${C_RESET}" ;;
        esac
      fi
      printf '  %s#%s%s %-9b %s %s(%s by @%s)%s\n' \
        "$C_CYAN" "$num" "$C_RESET" "$state_tag" "$title" \
        "$C_DIM" "$head" "$author" "$C_RESET"
    done <"$prs_tmp"
  else
    printf '  %s(none open)%s\n' "$C_DIM" "$C_RESET"
  fi
fi

# --- plans ------------------------------------------------------------------
# Reads .che/plans/*.md from the repo root. Each file may carry YAML
# frontmatter with `name`, `status` (open|in-progress|done|blocked), and
# optional `progress` (e.g. "60%" or "3/5"). Files without frontmatter are
# listed without a status badge.
if ! $short; then
  plans_dir="$repo_root/.che/plans"
  if [ -d "$plans_dir" ]; then
    # Glob safely: nullglob is non-portable, so check pattern manually.
    plans_found=false
    plans_header_printed=false
    for plan_file in "$plans_dir"/*.md; do
      [ -e "$plan_file" ] || continue
      base="$(basename "$plan_file" .md)"
      [ "$base" = "README" ] && continue
      plans_found=true

      FM_NAME=""; FM_STATUS=""; FM_PROGRESS=""
      frontmatter_parse_file "$plan_file"
      name="${FM_NAME:-$base}"

      if ! $plans_header_printed; then
        section "plans"
        plans_header_printed=true
      fi

      badge="$(frontmatter_status_badge "$FM_STATUS")"
      extra=""
      [ -n "$FM_PROGRESS" ] && extra=" ${C_DIM}(${FM_PROGRESS})${C_RESET}"
      printf '  %-11b %s%s %s(%s)%s\n' "$badge" "$name" "$extra" "$C_DIM" "$base.md" "$C_RESET"
    done
    if ! $plans_found && [ "${CHE_STATUS_SHOW_EMPTY:-0}" = "1" ]; then
      section "plans"
      printf '  %s(no plans in .che/plans/)%s\n' "$C_DIM" "$C_RESET"
    fi
  fi
fi

printf '\n'
