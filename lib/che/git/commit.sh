#!/usr/bin/env bash
# che commit — stage all changes, generate a commit message via local LLM, commit.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$LIB_DIR/provider.sh"
. "$LIB_DIR/ui.sh"
. "$LIB_DIR/git/push.sh"
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
  CHE_PROVIDER             claude-code (default) | ollama | copilot
  CHE_OLLAMA_HOST/MODEL    Ollama config (default model: llama3.2)
  CHE_MAX_DIFF_CHARS       diff truncation (default: 8000)

Persistent settings: 'che config provider <name>' (saved to ~/.che/config).
Requires: git, curl, python3 (or python), and a working LLM provider.
Run 'che doctor' to verify.
EOF
      exit 0
      ;;
    *) echo "che commit: unknown option '$1'" >&2; exit 1 ;;
  esac
  shift
done

for bin in git curl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing dependency: $bin" >&2; exit 1; }
done
if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  echo "missing dependency: python3 (or python) — install via brew/apt/winget" >&2
  exit 1
fi

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
You are generating a git commit message from a diff.

Format:
<title>
<blank line>
- <important point>
- <important point>
- <important point>

Rules:
- Reply with ONLY the commit message. No quotes, no explanation, no preamble.
- Output PLAIN TEXT only. No markdown formatting of any kind: no headers (#, ##), no bold (**X**), no italics, no code fences (\`\`\`), no nested lists.
- Title: one line, at least 4 words and max 72 characters, imperative mood starting with a verb (e.g. "add", "fix", "refactor"). Never a single word. The title must NOT be wrapped in ** or any other markup.
- Body: 2-5 bullets, each starting with "- " (dash space, never "* "), describing the important changes.
- Each bullet should be concise (max ~100 characters) and focus on what changed and why.
- Skip the body only if the change is trivial (e.g. typo fix, single-line tweak).
- If multiple unrelated changes, the title summarizes the dominant one; bullets cover the rest.

Diff:
$diff
EOF

fallback_msg() {
  local files n
  files="$(git diff --cached --name-only)"
  n="$(printf '%s\n' "$files" | awk 'NF{n++} END{print n+0}')"
  if [ "$n" = "1" ]; then
    printf 'update %s\n\n' "$(printf '%s\n' "$files" | awk 'NF{print; exit}')"
  else
    printf 'update %s files\n\n' "$n"
  fi
  printf '%s\n' "$files" | awk 'NF { printf "- %s\n", $0 }'
}

msg=""
provider_ensure_running >/dev/null 2>&1 || true

out_tmp="$(mktemp)"
err_tmp="$(mktemp)"
trap 'rm -f "$out_tmp" "$err_tmp"' EXIT

provider_smart_generate "$prompt" >"$out_tmp" 2>"$err_tmp" &
gen_pid=$!

if ui_spin "$gen_pid" "thinking via $(provider_active) ($(provider_active_model))"; then
  [ -s "$err_tmp" ] && cat "$err_tmp" >&2
  raw="$(cat "$out_tmp")"
  msg="$(printf '%s\n' "$raw" | awk '
    # Strip markdown formatting that small models emit despite being told not
    # to: fence lines, ATX headers (#), bold markers (**), and "* " bullets
    # (normalized to "- "). Underscores are left alone since they commonly
    # appear in identifiers a commit message might reference (e.g. __init__).
    /^[[:space:]]*```/ { next }
    {
      sub(/^[[:space:]]*#+[[:space:]]+/, "")
      gsub(/\*\*/, "")
      sub(/^\*[[:space:]]+/, "- ")
      print
    }
  ' | awk '
    NF && !seen { seen=1 }
    seen { buf[++n]=$0 }
    END {
      while (n > 0 && buf[n] ~ /^[[:space:]]*$/) n--
      for (i=1; i<=n; i++) print buf[i]
    }
  ' | awk 'NR==1 {
    sub(/^[[:space:]]+/, "")
    sub(/^["'"'"']/, ""); sub(/["'"'"']$/, "")
  } { print }' | awk '
    # Enforce git-commit convention: blank line between subject and body.
    # Without it, git treats the whole run-on block as one giant subject and
    # `git log %s` will smash it into one line (downstream: che status).
    NR==1 { print; need_blank=1; next }
    need_blank { if (NF) print ""; need_blank=0 }
    { print }
  ')"
  if [ -z "$(printf '%s\n' "$msg" | head -n 1)" ]; then
    echo "che commit: LLM returned empty message — using default message" >&2
    msg=""
  fi
else
  [ -s "$err_tmp" ] && cat "$err_tmp" >&2
  echo "che commit: message generation failed — using default message" >&2
  echo "             run 'che doctor provider' for diagnostics" >&2
fi

if [ -z "$msg" ]; then
  msg="$(fallback_msg)"
fi

title="$(printf '%s\n' "$msg" | head -n 1)"

printf '\n→ %s\n' "$title"
body="$(printf '%s\n' "$msg" | awk 'NR>1 && (NF || printed) { printed=1; print }')"
if [ -n "$body" ]; then
  printf '%s\n' "$body" | awk '{ print "  " $0 }'
fi
printf '\n'

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

msg_file="$(mktemp)"
trap 'rm -f "$out_tmp" "$err_tmp" "$msg_file"' EXIT
printf '%s\n' "$msg" >"$msg_file"

if $edit; then
  git commit -e -F "$msg_file"
else
  git commit -F "$msg_file"
fi

if $push; then
  git_push_with_recovery
fi
