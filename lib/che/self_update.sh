#!/usr/bin/env bash
# che self-update — hash-based staleness detection for the running che-cli
# install. Compares three SHAs:
#
#   installed_sha   — recorded by install.sh / install.ps1 in
#                     <prefix>/lib/che/.installed-version at install time
#   source_sha      — current HEAD of the source clone (recorded source_repo)
#   upstream_sha    — current HEAD of @{u} after `git fetch`
#
# States:
#   all equal               → up-to-date, silent
#   installed != source     → install stale (someone pulled but didn't reinstall)
#   source    != upstream   → source stale (need to pull from origin)
#   both                    → pull + reinstall
#
# Skip conditions:
#   CHE_NO_SELF_UPDATE=1
#   .installed-version missing (running from clone or pre-versioning install)
#   source repo missing or not a git repo
#   source repo dirty (uncommitted changes — would conflict with pull)
#   source repo on detached HEAD
#
# All output goes to stderr so callers can wrap this without contaminating stdout.

_self_update_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_self_update_log() { printf 'che self-update: %s\n' "$*" >&2; }

_self_update_read_kv() {
  # Reads `key=value` lines from a file into shell-locals — POSIX-safe (no
  # eval, no leading-whitespace assumptions). Strips trailing CR for files
  # written with Windows line endings.
  local file="$1" key="$2" line
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "$key="*) printf '%s' "${line#"$key="}"; return 0 ;;
    esac
  done < "$file"
  return 1
}

_self_update_short() {
  # Trim a SHA to 7 chars; pass-through if it's already short or non-SHA.
  local s="$1"
  if [ "${#s}" -ge 7 ]; then printf '%s' "${s:0:7}"; else printf '%s' "$s"; fi
}

_self_update_run_installer() {
  # Runs the source repo's installer with --no-deps --yes (lightweight).
  # On Windows, prefers PowerShell so winget/Copy-Item paths stay native.
  local repo="$1"
  local sh_path="$repo/install.sh"
  local ps_path="$repo/install.ps1"
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*)
      if [ -f "$ps_path" ] && command -v pwsh >/dev/null 2>&1; then
        pwsh -NoProfile -File "$ps_path" -AssumeYes -NoDeps
        return $?
      fi
      if [ -f "$ps_path" ] && command -v powershell >/dev/null 2>&1; then
        powershell -NoProfile -ExecutionPolicy Bypass -File "$ps_path" -AssumeYes -NoDeps
        return $?
      fi
      ;;
  esac
  if [ -f "$sh_path" ]; then
    bash "$sh_path" --no-deps --yes
    return $?
  fi
  _self_update_log "no installer found in $repo (tried install.sh, install.ps1)"
  return 1
}

# che_self_update_check
# Returns 0 always (best-effort — never fails the calling command).
# The user can disable entirely with CHE_NO_SELF_UPDATE=1.
che_self_update_check() {
  if [ "${CHE_NO_SELF_UPDATE:-0}" = "1" ]; then
    return 0
  fi

  local version_file="$_self_update_lib_dir/.installed-version"
  if [ ! -f "$version_file" ]; then
    # Either running from clone (development) or installed before we started
    # writing this file. Nothing to compare against — skip silently.
    return 0
  fi

  local source_repo installed_sha
  source_repo="$(_self_update_read_kv "$version_file" source_repo)" || return 0
  installed_sha="$(_self_update_read_kv "$version_file" installed_sha)" || return 0

  if [ -z "$source_repo" ] || [ ! -d "$source_repo/.git" ]; then
    _self_update_log "recorded source_repo '$source_repo' is not a git repo — skipping"
    return 0
  fi

  if ! git -C "$source_repo" symbolic-ref -q HEAD >/dev/null; then
    _self_update_log "source repo on detached HEAD — skipping"
    return 0
  fi

  if [ -n "$(git -C "$source_repo" status --porcelain 2>/dev/null)" ]; then
    _self_update_log "source repo has uncommitted changes — skipping (resolve manually)"
    return 0
  fi

  # Best-effort fetch with a hard timeout so a flaky network can't stall ship.
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 git -C "$source_repo" fetch --quiet 2>/dev/null || {
      _self_update_log "fetch failed or timed out — skipping"
      return 0
    }
  else
    git -C "$source_repo" fetch --quiet 2>/dev/null || {
      _self_update_log "fetch failed — skipping"
      return 0
    }
  fi

  local source_sha upstream_sha
  source_sha="$(git -C "$source_repo" rev-parse HEAD 2>/dev/null)" || return 0
  upstream_sha="$(git -C "$source_repo" rev-parse '@{u}' 2>/dev/null)" || {
    _self_update_log "no upstream tracking branch — skipping"
    return 0
  }

  local source_stale=false install_stale=false
  [ "$source_sha"   != "$upstream_sha"  ] && source_stale=true
  [ "$installed_sha" != "$source_sha"   ] && install_stale=true

  if ! $source_stale && ! $install_stale; then
    return 0
  fi

  # ---- there's something to update — show diagnostic + prompt ----
  printf '\n' >&2
  _self_update_log "che-cli install is out of date"
  printf '  source repo:    %s\n'  "$source_repo" >&2
  printf '  installed:      %s\n'  "$(_self_update_short "$installed_sha")" >&2
  printf '  source HEAD:    %s%s\n' \
    "$(_self_update_short "$source_sha")" \
    "$([ "$installed_sha" = "$source_sha" ] && printf ' (same)' || printf ' (differs)')" >&2
  printf '  upstream HEAD:  %s%s\n' \
    "$(_self_update_short "$upstream_sha")" \
    "$([ "$source_sha" = "$upstream_sha" ] && printf ' (same)' || printf ' (differs)')" >&2

  local action
  if $source_stale; then
    action="git pull --ff-only && install.sh --no-deps --yes"
  else
    action="install.sh --no-deps --yes"
  fi
  printf '  action:         %s\n\n' "$action" >&2

  # CHE_AUTO_SELF_UPDATE=1 skips the prompt (for non-interactive use).
  local answer
  if [ "${CHE_AUTO_SELF_UPDATE:-0}" = "1" ]; then
    answer=y
  else
    printf 'apply update now? [Y/n] ' >&2
    if ! IFS= read -r answer </dev/tty 2>/dev/null; then
      # No tty (e.g. piped invocation) — default to skip rather than block.
      _self_update_log "no tty for prompt — skipping (set CHE_AUTO_SELF_UPDATE=1 to auto-apply)"
      return 0
    fi
  fi
  case "${answer:-y}" in
    n|N|no|NO) _self_update_log "skipped by user"; return 0 ;;
  esac

  if $source_stale; then
    _self_update_log "pulling $source_repo ..."
    if ! git -C "$source_repo" pull --ff-only --quiet; then
      _self_update_log "ff-only pull failed — resolve manually in $source_repo and rerun"
      return 0
    fi
  fi

  _self_update_log "running installer (--no-deps --yes) ..."
  if _self_update_run_installer "$source_repo"; then
    _self_update_log "✓ updated to $(_self_update_short "$(git -C "$source_repo" rev-parse HEAD)")"
  else
    _self_update_log "installer reported errors — see output above"
  fi
  return 0
}
