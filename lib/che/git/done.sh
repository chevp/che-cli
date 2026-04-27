#!/usr/bin/env bash
# che done — finish the active che flow:
#   gh pr merge <pr> --squash --auto --delete-branch
#     (falls back to a direct squash merge if the repo has auto-merge disabled,
#      and auto-promotes the PR out of draft if needed)
#   git checkout <base> && git pull --ff-only && prune origin
#   delete the .git/che-flow marker.
set -euo pipefail

usage() {
  cat <<EOF
che done — finish the active che flow.

Reads .git/che-flow, then runs:
  gh pr merge <pr> --squash --auto --delete-branch
  git checkout <base> && git pull --ff-only && git remote prune origin

Aborts if there's no active flow, or no PR yet (run 'che ship' first).
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

for bin in git gh; do
  command -v "$bin" >/dev/null 2>&1 \
    || { echo "che done: missing dependency: $bin (run 'che doctor git')" >&2; exit 1; }
done

git rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "che done: not a git repository" >&2; exit 1; }

git_dir="$(git rev-parse --git-dir)"
marker="$git_dir/che-flow"

[ -f "$marker" ] \
  || { echo "che done: no active flow ($marker missing) — run 'che flow <branch>' first" >&2; exit 1; }

branch="$(awk -F= '$1=="branch"{print $2}' "$marker")"
base="$(awk -F=   '$1=="base"{print $2}'   "$marker")"
pr="$(awk -F=     '$1=="pr"{print $2}'     "$marker")"

[ -z "$branch" ] && { echo "che done: marker missing 'branch' field" >&2; exit 1; }
[ -z "$base" ]   && base="main"

if [ -z "$pr" ]; then
  echo "che done: no PR recorded yet — run 'che ship' first to create one" >&2
  exit 1
fi

cur="$(git rev-parse --abbrev-ref HEAD)"
if [ "$cur" != "$branch" ]; then
  echo "che done: HEAD is on '$cur' but flow branch is '$branch' — checkout it first" >&2
  exit 1
fi

# --auto: gh waits for required checks to pass, then squash-merges and deletes branch.
# Recoverable failures we transparently retry:
#   * enablePullRequestAutoMerge — repo has auto-merge disabled; retry without --auto
#   * "is still a draft"         — PR is draft; promote with `gh pr ready`, then retry
# Each recovery is guarded so we cannot loop on the same error twice.
err_log="$(mktemp)"
trap 'rm -f "$err_log"' EXIT
merge_mode="auto"
draft_promoted=0
while :; do
  rc=0
  if [ "$merge_mode" = "auto" ]; then
    gh pr merge "$pr" --squash --auto --delete-branch 2>"$err_log" || rc=$?
  else
    gh pr merge "$pr" --squash --delete-branch 2>"$err_log" || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then break; fi

  if [ "$merge_mode" = "auto" ] && grep -q 'enablePullRequestAutoMerge' "$err_log"; then
    echo "che done: auto-merge disabled on this repo — falling back to direct merge" >&2
    merge_mode="direct"
    continue
  fi
  if [ "$draft_promoted" -eq 0 ] && grep -q 'is still a draft' "$err_log"; then
    echo "che done: PR #$pr is a draft — marking ready, then retrying" >&2
    gh pr ready "$pr"
    draft_promoted=1
    continue
  fi
  cat "$err_log" >&2
  exit 1
done

git checkout "$base"
git pull --ff-only
git remote prune origin >/dev/null 2>&1 || true

# Local branch may already be gone (gh deletes it after merge); remove if still present.
if git show-ref --verify --quiet "refs/heads/$branch"; then
  git branch -D "$branch" >/dev/null 2>&1 || true
fi

rm -f "$marker"

if [ "$merge_mode" = "auto" ]; then
  printf '\n── flow done: PR #%s queued (auto-merge, squash, delete-branch) ──\n' "$pr"
else
  printf '\n── flow done: PR #%s merged (squash, delete-branch) ──\n' "$pr"
fi
printf 'back on %s\n' "$base"
