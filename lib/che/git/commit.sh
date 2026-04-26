#!/usr/bin/env bash
# che commit — stage all changes, generate a commit message via local LLM, commit.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$LIB_DIR/provider.sh"
provider_load

MAX_DIFF_CHARS="${CHE_MAX_DIFF_CHARS:-8000}"

push=false
dry=false
yes=false
edit=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    -p|--push)    push=true ;;
    -n|--dry-run) dry=true ;;
    -y|--yes)     yes=true ;;
    -e|--edit)    edit=true ;;
    -h|--help)
      cat <<EOF
che commit — stage all changes, generate a commit message via local LLM, commit.

Usage: che commit [options]

Options:
  -p, --push      push after commit
  -n, --dry-run   only print the generated message, do not commit
  -y, --yes       skip confirmation prompt
  -e, --edit      open editor to tweak the message before committing
  -h, --help      show this help

Environment:
  CHE_PROVIDER             ollama (default) | openai | anthropic
  CHE_OLLAMA_HOST/MODEL    Ollama config (default model: llama3.2)
  CHE_OPENAI_MODEL         OpenAI model     (needs OPENAI_API_KEY)
  CHE_ANTHROPIC_MODEL      Anthropic model  (needs ANTHROPIC_API_KEY)
  CHE_MAX_DIFF_CHARS       diff truncation (default: 8000)

Requires: git, curl, jq, and a working LLM provider.
Run 'che doctor' to verify.
EOF
      exit 0
      ;;
    *) echo "che commit: unknown option '$1'" >&2; exit 1 ;;
  esac
  shift
done

for bin in git curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing dependency: $bin" >&2; exit 1; }
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "che commit: not a git repository" >&2
  exit 1
fi

git add -A

diff="$(git diff --cached --no-color)"
if [ -z "$diff" ]; then
  echo "che commit: nothing staged, nothing to commit" >&2
  exit 0
fi

if [ "${#diff}" -gt "$MAX_DIFF_CHARS" ]; then
  diff="${diff:0:$MAX_DIFF_CHARS}

[diff truncated at $MAX_DIFF_CHARS chars]"
fi

read -r -d '' prompt <<EOF || true
You are generating a single git commit message from a diff.

Rules:
- Reply with ONLY the commit message. No quotes, no explanation, no preamble.
- One line, max 72 characters, imperative mood (e.g. "add", "fix", "refactor").
- If multiple unrelated changes, summarize the dominant one.

Diff:
$diff
EOF

if ! provider_ping; then
  echo "che commit: provider '$(provider_active)' not reachable" >&2
  echo "             run 'che doctor provider' for diagnostics" >&2
  exit 1
fi

raw="$(provider_generate "$prompt")" || {
  echo "che commit: provider '$(provider_active)' request failed" >&2
  exit 1
}

msg="$(printf '%s' "$raw" | head -n 1 \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^["'"'"']//; s/["'"'"']$//')"

if [ -z "$msg" ]; then
  echo "che commit: LLM returned empty message" >&2
  exit 1
fi

printf '\n→ %s\n\n' "$msg"

if $dry; then
  exit 0
fi

if ! $yes && ! $edit; then
  printf 'commit with this message? [Y/n/e=edit] '
  read -r answer
  case "$answer" in
    n|N) echo "aborted"; exit 1 ;;
    e|E) edit=true ;;
  esac
fi

if $edit; then
  git commit -em "$msg"
else
  git commit -m "$msg"
fi

if $push; then
  git push
fi
