#!/usr/bin/env bash
# Shared YAML frontmatter parser for che status (issues + plans) and
# che issue list. Recognizes the leading '---' / '---' block at the
# start of a text and extracts a small fixed set of fields:
#
#   name      free-form display name
#   status    open | in-progress | done | blocked  (anything else passes through)
#   progress  free-form, e.g. "60%" or "3/5 steps"
#
# Inline comments after a value (e.g. 'status: open  # foo') are stripped.
# Trailing '\r' from Windows-edited files is stripped.
#
# Usage:
#   frontmatter_parse_stdin <<<"$body"          # here-string — recommended
#   frontmatter_parse_stdin < <(printf '%s' x)  # process substitution
#   frontmatter_parse_file path/to/plan.md
#   echo "$FM_NAME / $FM_STATUS / $FM_PROGRESS"
#
# IMPORTANT: do NOT call as `echo "$x" | frontmatter_parse_stdin` — the
# pipeline runs the function in a subshell, so the FM_* globals never make
# it back to the caller. Always feed input via redirection.
#
# Both forms set the FM_* globals. Empty when unset / no frontmatter.

frontmatter_parse_stdin() {
  local fm
  fm="$(awk '
    NR==1 && /^---[[:space:]]*$/ {inside=1; next}
    inside && /^---[[:space:]]*$/ {exit}
    inside {print}
  ')"
  FM_NAME="$(_frontmatter_field "$fm" name)"
  FM_STATUS="$(_frontmatter_field "$fm" status)"
  FM_PROGRESS="$(_frontmatter_field "$fm" progress)"
}

frontmatter_parse_file() {
  frontmatter_parse_stdin <"$1"
}

_frontmatter_field() {
  local fm="$1" key="$2" val
  val="$(printf '%s\n' "$fm" | awk -v k="$key" '
    BEGIN { p = "^" k ":[[:space:]]*" }
    $0 ~ p {
      sub(p, "")
      sub(/[[:space:]]*#.*$/, "")  # strip inline comment
      sub(/[[:space:]]+$/, "")     # strip trailing whitespace
      print
      exit
    }
  ')"
  val="${val%$'\r'}"
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  printf '%s' "$val"
}

# Render a colored status badge for one of the well-known statuses.
# Pass the already-set color variables ($C_GREEN etc.) via the caller's env;
# this helper only assembles the string and prints it on stdout.
frontmatter_status_badge() {
  local status="$1"
  case "$status" in
    done)        printf '%sdone%s'        "${C_GREEN:-}" "${C_RESET:-}" ;;
    in-progress|in_progress|active)
                 printf '%sin-progress%s' "${C_YELLOW:-}" "${C_RESET:-}" ;;
    blocked)     printf '%sblocked%s'     "${C_RED:-}"   "${C_RESET:-}" ;;
    open|"")     printf '%sopen%s'        "${C_DIM:-}"   "${C_RESET:-}" ;;
    *)           printf '%s%s%s'          "${C_DIM:-}" "$status" "${C_RESET:-}" ;;
  esac
}
