#!/usr/bin/env bash
# Shared push helper used by `che commit --push` and `che ship`.
#
# git_push_with_recovery [git push args...]
#   - Runs `git push "$@"` with output captured.
#   - On a "rejected — fetch first" / "non-fast-forward" failure, runs
#     `git pull --rebase` and retries the push **once**.
#   - If the rebase produces conflicts, aborts the rebase and stops with the
#     conflicting paths surfaced — the LLM never touches conflict resolution.
#   - On any other failure (or after one failed retry), writes the captured
#     output + git state to $git_dir/che-last-error.log and prints a hint to
#     run `che explain` for an LLM-assisted diagnosis.
#
# Returns 0 on success, the underlying git exit code on failure.

if [ -t 1 ]; then
  PUSH_C_GREEN=$'\033[32m'; PUSH_C_RED=$'\033[31m'
  PUSH_C_DIM=$'\033[2m';    PUSH_C_RESET=$'\033[0m'
else
  PUSH_C_GREEN=""; PUSH_C_RED=""; PUSH_C_DIM=""; PUSH_C_RESET=""
fi

# Records a failure to $git_dir/che-last-error.log so `che explain` can read it.
_push_record_error() {
  local cmd="$1" exit_code="$2" output="$3"
  local git_dir; git_dir="$(git rev-parse --git-dir 2>/dev/null)" || return 0
  local log="$git_dir/che-last-error.log"

  {
    printf 'che-cli error log\n'
    printf 'timestamp: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'command:   %s\n' "$cmd"
    printf 'exit:      %s\n' "$exit_code"
    printf 'cwd:       %s\n' "$PWD"
    printf '\n--- output ---\n%s\n' "$output"
    printf '\n--- git status -sb ---\n'
    git status -sb 2>&1 || true
    printf '\n--- git log -5 --oneline ---\n'
    git log -5 --oneline 2>&1 || true
    printf '\n--- git remote -v ---\n'
    git remote -v 2>&1 || true
  } > "$log"
}

git_push_with_recovery() {
  local out tmp_out rc cmd
  cmd="git push $*"
  tmp_out="$(mktemp)"
  trap 'rm -f "$tmp_out"' RETURN

  set +e
  git push "$@" >"$tmp_out" 2>&1
  rc=$?
  set -e

  out="$(cat "$tmp_out")"

  if [ "$rc" -eq 0 ]; then
    cat "$tmp_out"
    return 0
  fi

  # Tier 1: known recoverable — non-fast-forward / fetch-first reject.
  # Suppress the noisy rejection blob; print one calm line and recover.
  if echo "$out" | grep -qE 'rejected.*(fetch first|non-fast-forward)|Updates were rejected'; then
    printf '%sche ship: remote moved — pulling --rebase, retrying push%s\n' \
      "$PUSH_C_DIM" "$PUSH_C_RESET" >&2

    local rebase_out rebase_rc
    rebase_out="$(git pull --rebase 2>&1)"
    rebase_rc=$?

    if [ "$rebase_rc" -ne 0 ]; then
      # Conflict or other rebase failure. Show what git push and rebase said
      # so the user can diagnose, then abort if mid-rebase.
      cat "$tmp_out"
      printf '%s%s%s\n' "$PUSH_C_DIM" "$rebase_out" "$PUSH_C_RESET"
      if git rev-parse --git-dir >/dev/null 2>&1 \
         && [ -d "$(git rev-parse --git-dir)/rebase-merge" -o -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
        printf '%sche ship: rebase produced conflicts — aborting%s\n' "$PUSH_C_RED" "$PUSH_C_RESET" >&2
        local conflicts; conflicts="$(git diff --name-only --diff-filter=U 2>/dev/null)"
        [ -n "$conflicts" ] && printf 'conflicting files:\n%s\n' "$conflicts" >&2
        git rebase --abort >/dev/null 2>&1 || true
        printf '%schanges left in working tree as before push; pull manually and resolve%s\n' \
          "$PUSH_C_DIM" "$PUSH_C_RESET" >&2
      fi
      _push_record_error "$cmd → pull --rebase failed" "$rebase_rc" "$rebase_out"
      printf '\nrun %sche explain%s for an LLM-assisted diagnosis\n' \
        "$PUSH_C_DIM" "$PUSH_C_RESET" >&2
      return "$rebase_rc"
    fi

    # Retry push, exactly once.
    set +e
    git push "$@" >"$tmp_out" 2>&1
    rc=$?
    set -e
    out="$(cat "$tmp_out")"

    if [ "$rc" -eq 0 ]; then
      cat "$tmp_out"
      printf '%s✓ push succeeded after rebase%s\n' "$PUSH_C_GREEN" "$PUSH_C_RESET" >&2
      return 0
    fi

    # Retry failed: now show both attempts so the user has full context.
    cat "$tmp_out"
    _push_record_error "$cmd (after pull --rebase)" "$rc" "$out"
    printf '\n%sche ship: push still failing after one retry%s\n' "$PUSH_C_RED" "$PUSH_C_RESET" >&2
    printf 'run %sche explain%s for an LLM-assisted diagnosis\n' \
      "$PUSH_C_DIM" "$PUSH_C_RESET" >&2
    return "$rc"
  fi

  # Unknown failure: surface the original output, record + advise.
  cat "$tmp_out"
  _push_record_error "$cmd" "$rc" "$out"
  printf '\n%sche ship: push failed (exit %d)%s\n' "$PUSH_C_RED" "$rc" "$PUSH_C_RESET" >&2
  printf 'run %sche explain%s for an LLM-assisted diagnosis\n' \
    "$PUSH_C_DIM" "$PUSH_C_RESET" >&2
  return "$rc"
}
