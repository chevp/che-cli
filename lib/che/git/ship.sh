#!/usr/bin/env bash
# che ship - for this repo and every submodule (recursively):
#   init if missing, fast-forward pull if on a branch, then add + commit + push.
#
# When this repo has an active che-flow marker (.git/che-flow), ship instead:
#   commit, push -u origin <branch>, and on first call open a draft PR via gh.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHE_BIN="${CHE_BIN:-$LIB_DIR/../../bin/che}"
. "$LIB_DIR/git/push.sh"

_ship_pull_network_error() {
  local err_file="$1"
  grep -Eiq "Could not resolve host:|Temporary failure in name resolution|Couldn't resolve host|Name or service not known" "$err_file"
}

_ship_pull_with_recovery() {
  local repo_root="$1"
  local repo_label="$2"
  local err_file pull_rc
  err_file="$(mktemp 2>/dev/null || printf '%s/.che-ship-pull.err' "$repo_root")"
  : > "$err_file"

  if ! git -C "$repo_root" symbolic-ref -q HEAD >/dev/null; then
    rm -f "$err_file" >/dev/null 2>&1 || true
    return 0
  fi

  if ! git -C "$repo_root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    rm -f "$err_file" >/dev/null 2>&1 || true
    return 0
  fi

  if git -C "$repo_root" pull --ff-only --autostash >/dev/null 2>"$err_file"; then
    rm -f "$err_file" >/dev/null 2>&1 || true
    return 0
  fi

  if _ship_pull_network_error "$err_file"; then
    printf 'che ship: network/DNS error while pulling %s - Git host could not be resolved\n' "$repo_label" >&2
    sed -n '1,3p' "$err_file" >&2
    printf 'che ship: check internet/VPN/proxy/DNS, then retry\n' >&2
    rm -f "$err_file" >/dev/null 2>&1 || true
    return 2
  fi

  echo "che ship: ff-only pull failed in $repo_label - trying pull --rebase --autostash" >&2
  : > "$err_file"
  if git -C "$repo_root" pull --rebase --autostash 2>"$err_file"; then
    rm -f "$err_file" >/dev/null 2>&1 || true
    return 0
  fi
  pull_rc=$?

  if _ship_pull_network_error "$err_file"; then
    printf 'che ship: network/DNS error while pulling %s - Git host could not be resolved\n' "$repo_label" >&2
    sed -n '1,3p' "$err_file" >&2
    printf 'che ship: check internet/VPN/proxy/DNS, then retry\n' >&2
    rm -f "$err_file" >/dev/null 2>&1 || true
    return 2
  fi

  rm -f "$err_file" >/dev/null 2>&1 || true
  return "${pull_rc:-1}"
}

# Self-update is only checked at the top-level ship invocation. Recursive
# submodule ships set CHE_SHIP_DEPTH for their children so the prompt fires
# at most once per user invocation.
if [ -z "${CHE_SHIP_DEPTH:-}" ]; then
  _is_top_level_ship=true
else
  _is_top_level_ship=false
fi
export CHE_SHIP_DEPTH=$((${CHE_SHIP_DEPTH:-0} + 1))

# _ship_finish <exit_code>
# Single exit point - runs the hash-based self-update check on a successful
# top-level ship, then exits with the original code. Failed ships skip the
# check (don't pile updates on top of an existing problem).
_ship_finish() {
  local rc="${1:-0}"
  if $_is_top_level_ship && [ "$rc" = "0" ]; then
    if [ -f "$LIB_DIR/self_update.sh" ]; then
      # shellcheck source=../self_update.sh
      . "$LIB_DIR/self_update.sh"
      che_self_update_check || true
    fi
  fi
  exit "$rc"
}

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "che ship: not a git repository" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --git-dir)"
marker="$git_dir/che-flow"

if [ -f "$repo_root/.gitmodules" ]; then
  failed_submodules=()

  while read -r sm_path; do
    [ -z "$sm_path" ] && continue

    sm_err="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/che_sm_err.$$")"
    if ! git -C "$repo_root" submodule update --init -- "$sm_path" 2>"$sm_err"; then
      failed_submodules+=("$sm_path (init failed)")
      if grep -qE "Repository not found|Authentication failed|could not read Username|Permission denied|terminal prompts disabled" "$sm_err" 2>/dev/null; then
        echo "che ship: $sm_path: no access to remote - skipping (continuing)" >&2
      else
        cat "$sm_err" >&2
        echo "che ship: submodule update failed for '$sm_path' - skipping (continuing)" >&2
      fi
      rm -f "$sm_err"
      continue
    fi
    [ -s "$sm_err" ] && cat "$sm_err" >&2
    rm -f "$sm_err"

    sm_abs="$repo_root/$sm_path"
    [ -e "$sm_abs/.git" ] || continue

    if git -C "$sm_abs" symbolic-ref -q HEAD >/dev/null; then
      set +e
      _ship_pull_with_recovery "$sm_abs" "$sm_path"
      pull_rc=$?
      set -e
      if [ "$pull_rc" -ne 0 ]; then
        echo "che ship: pull failed in $sm_path (continuing)"
      fi
    else
      echo "che ship: $sm_path is in detached HEAD, skipping pull"
    fi

    if ! ( cd "$sm_abs" && "$CHE_BIN" ship ); then
      failed_submodules+=("$sm_path (ship failed)")
      echo "che ship: ship failed in '$sm_path' (continuing)" >&2
    fi
  done < <(git -C "$repo_root" config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')

  if [ "${#failed_submodules[@]}" -gt 0 ]; then
    printf '\nche ship: %d submodule(s) had errors:\n' "${#failed_submodules[@]}" >&2
    for f in "${failed_submodules[@]}"; do
      printf '  - %s\n' "$f" >&2
    done
  fi
fi

# --- pull main repo before commit/push: ff-only first, fall back to rebase ---
if git -C "$repo_root" symbolic-ref -q HEAD >/dev/null \
   && git -C "$repo_root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  set +e
  _ship_pull_with_recovery "$repo_root" "$(basename "$repo_root")"
  pull_rc=$?
  set -e

  if [ "$pull_rc" -ne 0 ]; then
    if [ "$pull_rc" -eq 2 ]; then
      exit 1
    fi

    git_dir_pull="$(git -C "$repo_root" rev-parse --git-dir)"
    if [ -d "$git_dir_pull/rebase-merge" ] || [ -d "$git_dir_pull/rebase-apply" ]; then
      echo "che ship: rebase produced conflicts in $(basename "$repo_root") - invoking claude code" >&2
      # shellcheck source=conflicts.sh
      . "$LIB_DIR/git/conflicts.sh"
      rebase_done=false
      while true; do
        set +e
        ( cd "$repo_root" && conflicts_resolve_interactive )
        resolve_rc=$?
        set -e
        if [ "$resolve_rc" -ne 0 ]; then
          git -C "$repo_root" rebase --abort >/dev/null 2>&1 || true
          echo "che ship: conflicts unresolved - rebase aborted" >&2
          exit 1
        fi
        if GIT_EDITOR=true git -C "$repo_root" rebase --continue; then
          rebase_done=true
          break
        fi
        if [ -z "$(git -C "$repo_root" diff --name-only --diff-filter=U 2>/dev/null)" ]; then
          echo "che ship: rebase --continue failed unexpectedly - aborting" >&2
          git -C "$repo_root" rebase --abort >/dev/null 2>&1 || true
          exit 1
        fi
        echo "che ship: more conflicts on next commit - re-invoking claude code" >&2
      done
      $rebase_done && echo "che ship: rebase completed with claude assistance"
    else
      echo "che ship: pull failed in $(basename "$repo_root") - resolve manually and retry" >&2
      exit 1
    fi
  fi
fi

# --- flow mode: commit, push -u, open/update draft PR ---
if [ -f "$marker" ]; then
  branch="$(awk -F= '$1=="branch"{print $2}' "$marker")"
  base="$(awk -F= '$1=="base"{print $2}' "$marker")"
  pr="$(awk -F= '$1=="pr"{print $2}' "$marker")"
  [ -z "$base" ] && base="main"

  cur="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$cur" != "$branch" ]; then
    echo "che ship: marker says flow branch '$branch' but HEAD is '$cur'" >&2
    exit 1
  fi

  command -v gh >/dev/null 2>&1 \
    || { echo "che ship: missing dependency: gh (required in flow mode)" >&2; exit 1; }

  if [ -n "$pr" ]; then
    flow_label="flow: $branch -> $base, PR #$pr"
  else
    flow_label="flow: $branch -> $base"
  fi
  printf '\n-- repo: %s (%s) --\n' "$(basename "$repo_root")" "$flow_label"

  bash "$LIB_DIR/git/commit.sh" --yes
  git_push_with_recovery -u origin "$branch"

  if [ -z "$pr" ]; then
    if [ -z "$(git log "origin/$base..$branch" --oneline 2>/dev/null)" ]; then
      echo "che ship: no commits on '$branch' beyond '$base' yet - skipping PR creation" >&2
      _ship_finish 0
    fi
    new_pr_url="$(gh pr create --draft --fill --base "$base" --head "$branch")"
    new_pr="$(printf '%s\n' "$new_pr_url" | awk -F/ '/\/pull\//{print $NF}' | tr -d '\r\n')"
    if [ -n "$new_pr" ]; then
      printf 'pr=%s\n' "$new_pr" >> "$marker"
      printf '\n-> draft PR: %s\n' "$new_pr_url"
    else
      echo "che ship: failed to parse PR number from gh output: $new_pr_url" >&2
      _ship_finish 1
    fi
  else
    printf '\n-> updated PR #%s\n' "$pr"
  fi
  _ship_finish 0
fi

# --- default: existing behavior ---
if ! git -C "$repo_root" symbolic-ref -q HEAD >/dev/null; then
  detached_commit="$(git -C "$repo_root" rev-parse HEAD)"

  if [ -f "$marker" ]; then
    flow_branch="$(awk -F= '$1=="branch"{print $2}' "$marker")"
  else
    flow_branch=""
  fi

  recover_branch=""
  if [ -n "$flow_branch" ] && git -C "$repo_root" show-ref --verify --quiet "refs/heads/$flow_branch"; then
    recover_branch="$flow_branch"
  else
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

if [ -z "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ]; then
  printf '%s: clean\n' "$(basename "$repo_root")"
  _ship_finish 0
fi

printf '\n-- repo: %s --\n' "$(basename "$repo_root")"

if git -C "$repo_root" symbolic-ref -q HEAD >/dev/null; then
  bash "$LIB_DIR/git/commit.sh" --push --yes
  _ship_finish 0
else
  echo "che ship: still in detached HEAD, committing without push"
  bash "$LIB_DIR/git/commit.sh" --yes
  _ship_finish 0
fi
