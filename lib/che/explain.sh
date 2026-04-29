#!/usr/bin/env bash
# che explain — read-only LLM diagnosis of the most recent che ship/commit failure.
#
# When `git_push_with_recovery` (lib/che/git/push.sh) cannot recover a push,
# it writes the failed command + captured output + git state to
# $git_dir/che-last-error.log. `che explain` reads that log, asks the active
# provider for a one-line diagnosis and a single suggested next command,
# and prints the answer. It NEVER executes the suggestion — copy/paste is
# deliberate to keep the LLM out of the destructive path.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/provider.sh"
. "$LIB_DIR/ui.sh"
provider_load

usage() {
  cat <<EOF
che explain — ask the active LLM provider to diagnose the most recent
che ship/commit failure (read-only, never executes anything).

Usage:
  che explain                  # diagnose the last logged failure
  che explain "<question>"     # ad-hoc question with current git state
  che explain --show           # print the raw error log, do not call the LLM
  che explain --clear          # delete the error log

Where the log lives:
  <repo>/.git/che-last-error.log   (one per repo)

Provider is the same one used by che commit (CHE_PROVIDER, default: ollama).
Run 'che doctor provider' to verify the provider is reachable.

Docs: https://chevp.github.io/che-cli/
EOF
}

mode="explain"
question=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    --show)     mode="show" ;;
    --clear)    mode="clear" ;;
    -*)         echo "che explain: unknown option '$1'" >&2; exit 1 ;;
    *)
      [ -z "$question" ] || { echo "che explain: only one free-form question accepted" >&2; exit 1; }
      question="$1"
      ;;
  esac
  shift
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "che explain: not a git repository" >&2
  exit 1
fi

git_dir="$(git rev-parse --git-dir)"
log="$git_dir/che-last-error.log"

if [ "$mode" = "clear" ]; then
  if [ -f "$log" ]; then
    rm -f "$log"
    echo "che explain: cleared $log"
  else
    echo "che explain: no error log to clear"
  fi
  exit 0
fi

if [ "$mode" = "show" ]; then
  if [ -f "$log" ]; then
    cat "$log"
  else
    echo "che explain: no error log at $log" >&2
    exit 1
  fi
  exit 0
fi

# --- explain mode ---

# Gather context. Prefer the saved log; otherwise capture live state for
# free-form questions.
context=""
if [ -f "$log" ]; then
  context="$(cat "$log")"
else
  if [ -z "$question" ]; then
    cat >&2 <<EOF
che explain: no error log at $log

There has been no failed che ship/commit recorded in this repo. Either:
  - run 'che ship' / 'che commit --push' until something fails, or
  - pass a free-form question:  che explain "why is git push hanging?"
EOF
    exit 1
  fi
  context="$(
    printf '(no recorded failure — live git state)\n\n--- git status -sb ---\n'
    git status -sb 2>&1 || true
    printf '\n--- git log -5 --oneline ---\n'
    git log -5 --oneline 2>&1 || true
    printf '\n--- git remote -v ---\n'
    git remote -v 2>&1 || true
  )"
fi

# Trim very large logs; LLMs do not need megabytes of cargo.
MAX_CTX="${CHE_EXPLAIN_MAX_CHARS:-6000}"
if [ "${#context}" -gt "$MAX_CTX" ]; then
  context="${context:0:$MAX_CTX}

[context truncated at $MAX_CTX chars]"
fi

read -r -d '' prompt <<EOF || true
You are diagnosing a failed git or gh command for a developer.

Reply with EXACTLY this format and nothing else:

DIAGNOSIS: <one short sentence — what went wrong, in plain English>
COMMAND: <a single safe shell command they can run next, or "(none — manual investigation)">
WHY: <one short sentence — why that command should help>

Rules:
- Be specific to the captured output below; do NOT give generic git tips.
- The COMMAND must be a single line, copy-pasteable, and non-destructive
  unless the situation truly requires it. Prefer 'git status', 'git log',
  'git pull --rebase', 'git fetch' over force-push or reset --hard.
- If the situation needs human judgment (e.g. unresolved merge conflicts,
  ambiguous remote state), say so and put "(none — manual investigation)"
  in COMMAND.
- Do NOT suggest 'rm -rf', 'git push --force', 'git reset --hard' unless
  the captured output explicitly indicates the user already wants that.

${question:+User question: $question

}Captured context:
$context
EOF

provider_ensure_running >/dev/null 2>&1 || true
if ! provider_ping; then
  echo "che explain: provider '$(provider_active)' not reachable" >&2
  echo "             run 'che doctor provider' for diagnostics" >&2
  exit 1
fi

out_tmp="$(mktemp)"
err_tmp="$(mktemp)"
trap 'rm -f "$out_tmp" "$err_tmp"' EXIT

provider_generate "$prompt" >"$out_tmp" 2>"$err_tmp" &
gen_pid=$!

if ! ui_spin "$gen_pid" "diagnosing via $(provider_active) ($(provider_active_model))"; then
  [ -s "$err_tmp" ] && cat "$err_tmp" >&2
  echo "che explain: provider '$(provider_active)' request failed" >&2
  exit 1
fi

answer="$(cat "$out_tmp")"

if [ -z "$answer" ]; then
  echo "che explain: provider returned empty response" >&2
  exit 1
fi

printf '\n%s\n\n' "$answer"
printf 'note: this suggestion was NOT executed. Copy + paste if it looks right.\n' >&2
