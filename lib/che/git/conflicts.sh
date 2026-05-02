#!/usr/bin/env bash
# Interactive merge-conflict resolution backed by the Claude Code CLI.
#
# Triggered exclusively from `che ship` when its pre-push rebase produces
# conflicts. Not exposed as a standalone command — sourced into ship.sh and
# called via conflicts_resolve_interactive.
#
# We call `claude -p` directly (not through provider_smart_generate) because
# local Ollama models are too weak for non-trivial conflicts.
#
# Public entry points:
#   conflicts_list                       — print one path per line
#   conflicts_resolve_interactive        — loop over each conflicted file,
#                                          show claude's suggestion + diff,
#                                          let the user select an action
#
# Exit codes from conflicts_resolve_interactive:
#   0  all conflicts resolved (files staged with `git add`)
#   1  some files still conflicted (user skipped / claude unavailable)
#   3  user aborted (caller should `git rebase --abort` / `git merge --abort`)

CONFLICTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CONFLICTS_LIB_DIR/ui.sh"

if [ -t 1 ]; then
  CONF_C_DIM=$'\033[2m'; CONF_C_BOLD=$'\033[1m'
  CONF_C_GREEN=$'\033[32m'; CONF_C_YELLOW=$'\033[33m'
  CONF_C_RED=$'\033[31m'; CONF_C_CYAN=$'\033[36m'
  CONF_C_RESET=$'\033[0m'
else
  CONF_C_DIM=""; CONF_C_BOLD=""; CONF_C_GREEN=""; CONF_C_YELLOW=""
  CONF_C_RED=""; CONF_C_CYAN=""; CONF_C_RESET=""
fi

conflicts_list() {
  git diff --name-only --diff-filter=U 2>/dev/null
}

# Build the prompt sent to claude. Includes the conflicted file content,
# the list of incoming commits (when discoverable), and strict output rules.
_conflicts_build_prompt() {
  local file="$1" hint="${2:-}"
  local incoming
  if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    incoming="$(git log --oneline HEAD..MERGE_HEAD 2>/dev/null)"
  elif [ -d "$(git rev-parse --git-dir)/rebase-merge" ] \
    || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
    incoming="$(git log --oneline ORIG_HEAD..HEAD 2>/dev/null)"
  else
    incoming=""
  fi
  [ -z "$incoming" ] && incoming="(no merge head info available)"

  cat <<EOF
You are resolving a git merge conflict in a single file.

File: $file

The file currently contains conflict markers (<<<<<<<, =======, >>>>>>>).
Resolve ALL conflicts and output ONLY the complete resolved file content.
No markers, no preamble, no commentary, no markdown code fences.
Preserve indentation, imports, and surrounding code exactly.

When the two sides conflict in intent, prefer the change that:
  - looks more complete (more fields, more error handling),
  - matches the surrounding code style,
  - or is consistent with the incoming commit messages below.

=== incoming commits (HEAD..MERGE_HEAD or ORIG_HEAD..HEAD) ===
$incoming
${hint:+

=== user hint ===
$hint
}
=== file content with conflict markers ===
$(cat "$file")
EOF
}

# Run claude on a single file, write the proposed resolution to $out_path.
# Returns 0 on success, non-zero on failure.
_conflicts_call_claude() {
  local file="$1" out_path="$2" hint="${3:-}"
  local prompt err_tmp
  prompt="$(_conflicts_build_prompt "$file" "$hint")"
  err_tmp="$(mktemp)"

  # --tools "" disables every tool: the prompt asks for the resolved file
  # content as plain text, and AskUserQuestion in -p mode would hang the
  # subprocess (no callback path back to the parent shell).
  printf '%s' "$prompt" | claude -p --tools "" >"$out_path" 2>"$err_tmp" &
  local pid=$!
  if ! ui_spin "$pid" "claude resolving $(basename "$file")"; then
    [ -s "$err_tmp" ] && cat "$err_tmp" >&2
    rm -f "$err_tmp"
    return 1
  fi
  rm -f "$err_tmp"

  if [ ! -s "$out_path" ]; then
    printf '%sche: claude returned empty output for %s%s\n' \
      "$CONF_C_RED" "$file" "$CONF_C_RESET" >&2
    return 1
  fi
  if grep -qE '^(<<<<<<< |=======$|>>>>>>> )' "$out_path"; then
    printf '%sche: claude output still contains conflict markers for %s%s\n' \
      "$CONF_C_YELLOW" "$file" "$CONF_C_RESET" >&2
    return 1
  fi
  return 0
}

_conflicts_show_diff() {
  local original="$1" resolved="$2" file="$3"
  printf '\n%s── proposed resolution: %s ──%s\n' \
    "$CONF_C_BOLD" "$file" "$CONF_C_RESET"
  if command -v git >/dev/null 2>&1; then
    git --no-pager diff --no-index --color=always -- "$original" "$resolved" || true
  else
    diff -u "$original" "$resolved" || true
  fi
}

# Resolve a single file. Returns:
#   0 accepted  |  2 skipped  |  3 abort all
conflicts_resolve_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    printf '%sche: %s is not a regular file (likely add/delete conflict) — skipping%s\n' \
      "$CONF_C_YELLOW" "$file" "$CONF_C_RESET" >&2
    return 2
  fi

  local resolved_tmp; resolved_tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$resolved_tmp'" RETURN

  if ! _conflicts_call_claude "$file" "$resolved_tmp"; then
    printf '%sche: claude could not resolve %s — leaving conflict in place%s\n' \
      "$CONF_C_YELLOW" "$file" "$CONF_C_RESET" >&2
    return 2
  fi

  _conflicts_show_diff "$file" "$resolved_tmp" "$file"

  while true; do
    printf '\n%sselect:%s [%sa%s]ccept  [%so%s]urs  [%st%s]heirs  [%se%s]dit  [%sr%s]etry+hint  [%ss%s]kip  [%sq%s]uit > ' \
      "$CONF_C_BOLD" "$CONF_C_RESET" \
      "$CONF_C_GREEN" "$CONF_C_RESET" \
      "$CONF_C_CYAN"  "$CONF_C_RESET" \
      "$CONF_C_CYAN"  "$CONF_C_RESET" \
      "$CONF_C_CYAN"  "$CONF_C_RESET" \
      "$CONF_C_CYAN"  "$CONF_C_RESET" \
      "$CONF_C_DIM"   "$CONF_C_RESET" \
      "$CONF_C_RED"   "$CONF_C_RESET"
    local choice
    if ! read -r choice </dev/tty; then
      printf '\n%sche: no tty — cannot prompt, skipping %s%s\n' \
        "$CONF_C_YELLOW" "$file" "$CONF_C_RESET" >&2
      return 2
    fi

    case "$choice" in
      a|A|"")
        cp "$resolved_tmp" "$file"
        git add -- "$file"
        printf '%s✓ accepted %s%s\n' "$CONF_C_GREEN" "$file" "$CONF_C_RESET"
        return 0
        ;;
      o|O)
        if git checkout --ours -- "$file" 2>/dev/null; then
          git add -- "$file"
          printf '%s✓ kept ours for %s%s\n' "$CONF_C_GREEN" "$file" "$CONF_C_RESET"
          return 0
        else
          printf '%sche: git checkout --ours failed for %s%s\n' \
            "$CONF_C_RED" "$file" "$CONF_C_RESET" >&2
        fi
        ;;
      t|T)
        if git checkout --theirs -- "$file" 2>/dev/null; then
          git add -- "$file"
          printf '%s✓ kept theirs for %s%s\n' "$CONF_C_GREEN" "$file" "$CONF_C_RESET"
          return 0
        else
          printf '%sche: git checkout --theirs failed for %s%s\n' \
            "$CONF_C_RED" "$file" "$CONF_C_RESET" >&2
        fi
        ;;
      e|E)
        cp "$resolved_tmp" "$file"
        "${EDITOR:-vi}" "$file" </dev/tty >/dev/tty 2>/dev/tty
        if grep -qE '^(<<<<<<< |=======$|>>>>>>> )' "$file"; then
          printf '%sche: %s still has conflict markers — re-prompting%s\n' \
            "$CONF_C_YELLOW" "$file" "$CONF_C_RESET" >&2
          continue
        fi
        git add -- "$file"
        printf '%s✓ edited and accepted %s%s\n' "$CONF_C_GREEN" "$file" "$CONF_C_RESET"
        return 0
        ;;
      r|R)
        printf 'hint for claude (one line): '
        local hint
        if ! read -r hint </dev/tty; then hint=""; fi
        if _conflicts_call_claude "$file" "$resolved_tmp" "$hint"; then
          _conflicts_show_diff "$file" "$resolved_tmp" "$file"
        fi
        ;;
      s|S)
        printf '%s↷ skipped %s (still conflicted)%s\n' \
          "$CONF_C_YELLOW" "$file" "$CONF_C_RESET" >&2
        return 2
        ;;
      q|Q)
        return 3
        ;;
      *)
        printf '%sunknown choice: %s%s\n' "$CONF_C_DIM" "$choice" "$CONF_C_RESET" >&2
        ;;
    esac
  done
}

conflicts_resolve_interactive() {
  if ! command -v claude >/dev/null 2>&1; then
    printf '%sche: claude CLI not on PATH — install from https://docs.claude.com/claude-code%s\n' \
      "$CONF_C_RED" "$CONF_C_RESET" >&2
    return 1
  fi

  local files; files="$(conflicts_list)"
  if [ -z "$files" ]; then
    printf 'che: no conflicts to resolve\n'
    return 0
  fi

  local total; total="$(printf '%s\n' "$files" | awk 'NF{n++} END{print n+0}')"
  printf '\n%sche: %d file(s) with conflicts — invoking claude code for suggestions%s\n' \
    "$CONF_C_BOLD" "$total" "$CONF_C_RESET"

  local i=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    i=$((i + 1))
    printf '\n%s── [%d/%d] %s ──%s\n' \
      "$CONF_C_BOLD" "$i" "$total" "$f" "$CONF_C_RESET"
    set +e
    conflicts_resolve_file "$f"
    local rc=$?
    set -e
    case "$rc" in
      0) ;;
      2) ;;
      3)
        printf '\n%sche: aborted by user%s\n' "$CONF_C_RED" "$CONF_C_RESET" >&2
        return 3
        ;;
    esac
  done <<< "$files"

  local remaining; remaining="$(conflicts_list | awk 'NF{n++} END{print n+0}')"
  if [ "$remaining" -gt 0 ]; then
    printf '\n%sche: %d file(s) still conflicted — resolve manually and retry%s\n' \
      "$CONF_C_YELLOW" "$remaining" "$CONF_C_RESET" >&2
    return 1
  fi

  printf '\n%s✓ all conflicts resolved%s\n' "$CONF_C_GREEN" "$CONF_C_RESET"
  return 0
}

