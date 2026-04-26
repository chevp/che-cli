#!/usr/bin/env bash
# che ship — for this repo and every submodule (recursively):
#   init if missing, fast-forward pull if on a branch, then add + commit + push.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHE_BIN="${CHE_BIN:-$LIB_DIR/../../bin/che}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "che ship: not a git repository" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"

if [ -f "$repo_root/.gitmodules" ]; then
  git -C "$repo_root" submodule update --init

  while read -r sm_path; do
    [ -z "$sm_path" ] && continue
    sm_abs="$repo_root/$sm_path"
    [ -e "$sm_abs/.git" ] || continue

    printf '\n── submodule: %s ──\n' "$sm_path"

    if git -C "$sm_abs" symbolic-ref -q HEAD >/dev/null; then
      git -C "$sm_abs" pull --ff-only \
        || echo "che ship: pull failed in $sm_path (continuing)"
    else
      echo "che ship: $sm_path is in detached HEAD, skipping pull"
    fi

    ( cd "$sm_abs" && "$CHE_BIN" ship )
  done < <(git -C "$repo_root" config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
fi

printf '\n── repo: %s ──\n' "$(basename "$repo_root")"
exec bash "$LIB_DIR/git/commit.sh" --push --yes
