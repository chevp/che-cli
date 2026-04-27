#!/usr/bin/env bash
# che issue — manage GitHub issues for the current repo via the gh CLI,
# with AI-generated title/body (analogue to `che commit`).
#
# Subcommands:
#   create [description]  open a new issue. Description is free text; if
#                         omitted, the LLM is prompted with the recent diff
#                         and the active branch name as hints.
#   list                  list open issues for the current repo
#   close <n> [--reason]  close issue #n
#
# `che issue` (no subcommand) is shorthand for `che issue create`.
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/provider.sh"
. "$LIB_DIR/ui.sh"

if [ -t 1 ]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
  C_RESET=$'\033[0m'
else
  C_BOLD=""; C_DIM=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_RESET=""
fi

usage() {
  cat <<EOF
che issue — manage GitHub issues via gh, with AI-generated content.

Usage:
  che issue [create] [description]   open a new issue (LLM drafts title/body)
  che issue list [--limit N]         list open issues for the current repo
  che issue close <n> [--reason R]   close issue #n
  che issue -h | --help              show this help

Notes:
  - 'create' without a description uses the current branch name and a short
    diff summary as hints. With a description, the LLM uses that as the seed.
  - All forms require 'gh' installed and authenticated. Run 'che doctor git'
    to verify.
  - The repo is determined by 'gh' from the local origin remote.

Environment:
  CHE_PROVIDER             ollama (default) | claude-code | copilot
  CHE_MAX_DIFF_CHARS       diff truncation for the create prompt (default: 4000)
EOF
}

require_gh() {
  command -v gh >/dev/null 2>&1 \
    || { echo "che issue: missing dependency: gh — run 'che doctor git'" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 \
    || { echo "che issue: gh not authenticated — run 'gh auth login'" >&2; exit 1; }
}

cmd_list() {
  require_gh
  local limit=10
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      -h|--help) echo "Usage: che issue list [--limit N]"; exit 0 ;;
      *) echo "che issue list: unknown option '$1'" >&2; exit 1 ;;
    esac
  done

  local rows
  rows="$(gh issue list --state open --limit "$limit" \
            --json number,title,labels,assignees \
            --jq '.[] | "\(.number)\t\(.title)\t\([.labels[].name]|join(","))\t\([.assignees[].login]|join(","))"' \
            2>/dev/null)" || {
    echo "che issue list: 'gh issue list' failed — is this a GitHub repo?" >&2
    exit 1
  }

  if [ -z "$rows" ]; then
    printf '  %s(no open issues)%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  printf '%s\n' "$rows" | while IFS=$'\t' read -r num title labels assignees; do
    local meta=""
    [ -n "$labels" ]    && meta="${meta} ${C_DIM}[${labels}]${C_RESET}"
    [ -n "$assignees" ] && meta="${meta} ${C_DIM}@${assignees}${C_RESET}"
    printf '  %s#%s%s %s%s\n' "$C_CYAN" "$num" "$C_RESET" "$title" "$meta"
  done
}

cmd_close() {
  require_gh
  local num="" reason=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      -h|--help) echo "Usage: che issue close <n> [--reason R]"; exit 0 ;;
      -*) echo "che issue close: unknown option '$1'" >&2; exit 1 ;;
      *) num="$1"; shift ;;
    esac
  done
  [ -z "$num" ] && { echo "che issue close: issue number required" >&2; exit 1; }

  if [ -n "$reason" ]; then
    gh issue close "$num" --comment "$reason"
  else
    gh issue close "$num"
  fi
}

# Build a hint block for the LLM: branch name + diff summary, truncated.
_create_hints() {
  local branch diff
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")"
  diff="$(git diff --no-color HEAD 2>/dev/null)"
  local max="${CHE_MAX_DIFF_CHARS:-4000}"
  if [ "${#diff}" -gt "$max" ]; then
    diff="${diff:0:$max}

[diff truncated at $max chars]"
  fi
  printf 'Branch: %s\n' "$branch"
  if [ -n "$diff" ]; then
    printf '\nLocal changes (uncommitted, may or may not be related):\n%s\n' "$diff"
  else
    printf '\n(no uncommitted local changes)\n'
  fi
}

cmd_create() {
  require_gh
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "che issue create: not a git repository" >&2
    exit 1
  fi

  local description="" yes=false dry=false edit=false labels=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes)     yes=true; shift ;;
      -n|--dry-run) dry=true; shift ;;
      -e|--edit)    edit=true; shift ;;
      -l|--label)   labels="$2"; shift 2 ;;
      -h|--help)
        cat <<EOF
Usage: che issue create [options] [description]

Options:
  -y, --yes        skip confirmation
  -n, --dry-run    print the drafted issue, do not open it
  -e, --edit       open editor before submitting
  -l, --label L    comma-separated labels to apply
EOF
        exit 0
        ;;
      --) shift; description="$*"; break ;;
      -*) echo "che issue create: unknown option '$1'" >&2; exit 1 ;;
      *)  description="${description:+$description }$1"; shift ;;
    esac
  done

  local hints; hints="$(_create_hints)"
  local seed
  if [ -n "$description" ]; then
    seed="User-provided description (this is the primary intent — use it):
$description

Repository hints (for additional context only):
$hints"
  else
    seed="No user description was provided. Infer the issue from the repository hints below.

$hints"
  fi

  local prompt
  read -r -d '' prompt <<EOF || true
You are drafting a GitHub issue.

Format:
<title>
<blank line>
<body>

Rules:
- Reply with ONLY the issue text. No quotes, no preamble, no explanation.
- Title: one line, 4–72 characters, imperative or descriptive (e.g.
  "Fix race in workflow loader", "Document plans/ directory layout").
  Never start with a verb in past tense.
- Body: GitHub-flavored markdown. Use sections only when relevant:
  ## Context  — what / where in the code
  ## Steps to reproduce  — only for bugs
  ## Expected / Actual  — only for bugs
  ## Proposal  — for features / refactors
- Keep it concise. 4-15 lines is typical. Avoid filler.
- If the user description is unclear, mention that explicitly at the top
  of the body so a human can refine it.

Input:
$seed
EOF

  provider_ensure_running >/dev/null 2>&1 || true

  local out_tmp err_tmp
  out_tmp="$(mktemp)"; err_tmp="$(mktemp)"
  trap 'rm -f "$out_tmp" "$err_tmp"' EXIT

  provider_smart_generate "$prompt" >"$out_tmp" 2>"$err_tmp" &
  local gen_pid=$!

  if ! ui_spin "$gen_pid" "drafting issue via $(provider_active) ($(provider_active_model))"; then
    [ -s "$err_tmp" ] && cat "$err_tmp" >&2
    echo "che issue: LLM draft failed — run 'che doctor provider' for diagnostics" >&2
    exit 1
  fi
  [ -s "$err_tmp" ] && cat "$err_tmp" >&2

  local raw msg
  raw="$(cat "$out_tmp")"
  msg="$(printf '%s\n' "$raw" | awk '
    NF && !seen { seen=1 }
    seen { buf[++n]=$0 }
    END {
      while (n > 0 && buf[n] ~ /^[[:space:]]*$/) n--
      for (i=1; i<=n; i++) print buf[i]
    }
  ')"

  local title body
  title="$(printf '%s\n' "$msg" | head -n 1 | sed -E 's/^[[:space:]]+//; s/^["'"'"']//; s/["'"'"']$//')"
  body="$(printf '%s\n' "$msg" | awk 'NR>1 && (NF || printed) { printed=1; print }')"

  if [ -z "$title" ]; then
    echo "che issue: LLM returned an empty title — aborting" >&2
    exit 1
  fi

  printf '\n%sTitle:%s %s\n' "$C_BOLD" "$C_RESET" "$title"
  if [ -n "$body" ]; then
    printf '\n%sBody:%s\n' "$C_BOLD" "$C_RESET"
    printf '%s\n' "$body" | awk '{ print "  " $0 }'
  fi
  printf '\n'

  if $dry; then
    return 0
  fi

  if ! $yes && ! $edit; then
    printf 'open this issue? [Y/n/e=edit] '
    local answer; read -r answer
    case "$answer" in
      n|N) echo "aborted"; exit 1 ;;
      e|E) edit=true ;;
    esac
  fi

  if $edit; then
    local body_file; body_file="$(mktemp --suffix=.md 2>/dev/null || mktemp)"
    {
      printf '%s\n\n' "$title"
      printf '%s\n' "$body"
    } >"$body_file"
    "${EDITOR:-vi}" "$body_file"
    title="$(head -n 1 "$body_file")"
    body="$(awk 'NR==1 {next} NR==2 && !NF {next} { print }' "$body_file")"
    rm -f "$body_file"
  fi

  local args=( --title "$title" --body "${body:-_(no body)_}" )
  if [ -n "$labels" ]; then
    args+=( --label "$labels" )
  fi

  local url
  if ! url="$(gh issue create "${args[@]}")"; then
    echo "che issue: gh issue create failed" >&2
    exit 1
  fi
  printf '%s→ opened:%s %s\n' "$C_GREEN" "$C_RESET" "$url"
}

case "${1:-create}" in
  -h|--help) usage; exit 0 ;;
  create)    shift; cmd_create "$@" ;;
  list)      shift; cmd_list "$@" ;;
  close)     shift; cmd_close "$@" ;;
  *)
    # Treat unknown first arg as description for `create`.
    cmd_create "$@"
    ;;
esac
