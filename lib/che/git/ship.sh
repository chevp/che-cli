#!/usr/bin/env bash
# che ship — for this repo and every submodule (recursively):
#   init if missing, fast-forward pull if on a branch, then add + commit + push.
#
# When this repo has an active che-flow marker (.git/che-flow), ship instead:
#   commit, push -u origin <branch>, and on first call open a draft PR via gh.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHE_BIN="${CHE_BIN:-$LIB_DIR/../../bin/che}"
. "$LIB_DIR/git/push.sh"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "che ship: not a git repository" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --git-dir)"
marker="$git_dir/che-flow"

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

# --- pull main repo before commit/push: ff-only first, fall back to rebase ---
if git -C "$repo_root" symbolic-ref -q HEAD >/dev/null \
   && git -C "$repo_root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  if ! git -C "$repo_root" pull --ff-only --autostash >/dev/null 2>&1; then
    echo "che ship: ff-only pull failed in $(basename "$repo_root") — trying pull --rebase --autostash" >&2
    if ! git -C "$repo_root" pull --rebase --autostash; then
      git_dir_pull="$(git -C "$repo_root" rev-parse --git-dir)"
      if [ -d "$git_dir_pull/rebase-merge" ] || [ -d "$git_dir_pull/rebase-apply" ]; then
        conflicts="$(git -C "$repo_root" diff --name-only --diff-filter=U 2>/dev/null)"
        echo "che ship: rebase produced conflicts in $(basename "$repo_root") — aborting" >&2
        [ -n "$conflicts" ] && printf 'conflicting files:\n%s\n' "$conflicts" >&2
        git -C "$repo_root" rebase --abort >/dev/null 2>&1 || true
      fi
      echo "che ship: pull failed in $(basename "$repo_root") — resolve manually and retry" >&2
      exit 1
    fi
  fi
fi

# --- flow mode: commit, push -u, open/update draft PR ---
if [ -f "$marker" ]; then
  branch="$(awk -F= '$1=="branch"{print $2}' "$marker")"
  base="$(awk -F=   '$1=="base"{print $2}'   "$marker")"
  pr="$(awk -F=     '$1=="pr"{print $2}'     "$marker")"
  [ -z "$base" ] && base="main"

  cur="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$cur" != "$branch" ]; then
    echo "che ship: marker says flow branch '$branch' but HEAD is '$cur'" >&2
    exit 1
  fi

  command -v gh >/dev/null 2>&1 \
    || { echo "che ship: missing dependency: gh (required in flow mode)" >&2; exit 1; }

  if [ -n "$pr" ]; then
    flow_label="flow: $branch → $base, PR #$pr"
  else
    flow_label="flow: $branch → $base"
  fi
  printf '\n── repo: %s (%s) ──\n' "$(basename "$repo_root")" "$flow_label"

  # Stage + AI commit (no --push: we need -u origin on first push).
  bash "$LIB_DIR/git/commit.sh" --yes

  # Push (sets upstream on first call; cheap to repeat).
  git_push_with_recovery -u origin "$branch"

  # Open draft PR on first call.
  if [ -z "$pr" ]; then
    if [ -z "$(git log "origin/$base..$branch" --oneline 2>/dev/null)" ]; then
      echo "che ship: no commits on '$branch' beyond '$base' yet — skipping PR creation" >&2
      exit 0
    fi
    new_pr_url="$(gh pr create --draft --fill --base "$base" --head "$branch")"
    new_pr="$(printf '%s\n' "$new_pr_url" | awk -F/ '/\/pull\//{print $NF}' | tr -d '\r\n')"
    if [ -n "$new_pr" ]; then
      printf 'pr=%s\n' "$new_pr" >> "$marker"
      printf '\n→ draft PR: %s\n' "$new_pr_url"
    else
      echo "che ship: failed to parse PR number from gh output: $new_pr_url" >&2
      exit 1
    fi
  else
    printf '\n→ updated PR #%s\n' "$pr"
  fi
  exit 0
fi

# --- default: existing behavior ---
printf '\n── repo: %s ──\n' "$(basename "$repo_root")"

# Check if HEAD is detached and recover automatically
if ! git -C "$repo_root" symbolic-ref -q HEAD >/dev/null; then
  detached_commit="$(git -C "$repo_root" rev-parse HEAD)"

  # Prefer the active che-flow branch if a marker exists.
  if [ -f "$marker" ]; then
    flow_branch="$(awk -F= '$1=="branch"{print $2}' "$marker")"
  else
    flow_branch=""
  fi

  recover_branch=""
  if [ -n "$flow_branch" ] && git -C "$repo_root" show-ref --verify --quiet "refs/heads/$flow_branch"; then
    recover_branch="$flow_branch"
  else
    # for-each-ref refs/heads/ only returns real local branches — unlike
    # `git branch --contains`, which prepends "(HEAD detached at <sha>)" and
    # would otherwise trip up `head -n 1`.
    recover_branch="$(git -C "$repo_root" for-each-ref --format='%(refname:short)' --contains "$detached_commit" refs/heads/ 2>/dev/null | head -n 1 | tr -d '\r')"
  fi

  if [ -n "$recover_branch" ]; then
    git -C "$repo_root" checkout "$recover_branch" >/dev/null 2>&1 \
      && echo "che ship: recovered from detached HEAD, switched to '$recover_branch'" \
      || echo "che ship: detached HEAD at $detached_commit (could not recover to '$recover_branch')"
  else
    echo "che ship: detached HEAD at $detached_commit (no branch contains this commit)"
  fi
fi

if git -C "$repo_root" symbolic-ref -q HEAD >/dev/null; then
  exec bash "$LIB_DIR/git/commit.sh" --push --yes
else
  echo "che ship: still in detached HEAD, committing without push"
  exec bash "$LIB_DIR/git/commit.sh" --yes
fi
