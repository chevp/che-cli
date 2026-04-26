#!/usr/bin/env bash
# che flow <branch> — start a feature branch backed by a GitHub PR.
# Pulls base, creates the branch, writes .git/che-flow so that subsequent
# `che ship` calls push and (on first call) open a draft PR, and `che done`
# can squash-merge it via gh and return to base.
set -euo pipefail

usage() {
  cat <<EOF
che flow — start a flow branch (pull base, checkout new, mark for che ship/done).

Usage: che flow <branch> [--base <branch>]

Options:
  --base <branch>   base branch (default: main)
  -h, --help        show this help

Workflow:
  che flow feat/foo     # pull main, checkout feat/foo, write marker
  ...edit...
  che ship              # commit + push -u (creates draft PR on first call)
  ...edit...
  che ship              # commit + push (PR auto-updates)
  che done              # gh pr merge --squash --auto --delete-branch + back to base
EOF
}

base="main"
branch=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --base)
      shift
      base="${1:-}"
      [ -z "$base" ] && { echo "che flow: --base needs a value" >&2; exit 1; }
      ;;
    -*) echo "che flow: unknown option '$1'" >&2; exit 1 ;;
    *)
      [ -n "$branch" ] && { echo "che flow: only one branch arg accepted" >&2; exit 1; }
      branch="$1"
      ;;
  esac
  shift
done

[ -z "$branch" ] && { echo "che flow: missing <branch>" >&2; usage >&2; exit 1; }

for bin in git gh; do
  command -v "$bin" >/dev/null 2>&1 \
    || { echo "che flow: missing dependency: $bin (run 'che doctor git')" >&2; exit 1; }
done

git rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "che flow: not a git repository" >&2; exit 1; }

gh auth status >/dev/null 2>&1 \
  || { echo "che flow: gh not authenticated — run: gh auth login" >&2; exit 1; }

git_dir="$(git rev-parse --git-dir)"
marker="$git_dir/che-flow"

if [ -f "$marker" ]; then
  cur_branch="$(awk -F= '$1=="branch"{print $2}' "$marker")"
  echo "che flow: active flow on '$cur_branch' — run 'che done' first or rm $marker" >&2
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "che flow: local branch '$branch' already exists" >&2
  exit 1
fi

git fetch origin --prune

git show-ref --verify --quiet "refs/heads/$base" \
  || { echo "che flow: base branch '$base' does not exist locally" >&2; exit 1; }

git checkout "$base"
git pull --ff-only
git checkout -b "$branch"

{
  printf 'branch=%s\n' "$branch"
  printf 'base=%s\n'   "$base"
} > "$marker"

printf '\n── flow started: %s (base: %s) ──\n' "$branch" "$base"
printf 'next: edit, then "che ship" to commit + push (draft PR on first call)\n'
