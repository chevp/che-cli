#!/usr/bin/env bash
# che self-update - hash-based staleness detection for the running che-cli install.

_self_update_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_self_update_log() { printf 'che self-update: %s\n' "$*" >&2; }

_self_update_read_kv() {
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
  local s="$1"
  if [ "${#s}" -ge 7 ]; then printf '%s' "${s:0:7}"; else printf '%s' "$s"; fi
}

_self_update_run_installer() {
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

che_self_update_check() {
  if [ "${CHE_NO_SELF_UPDATE:-0}" = "1" ]; then
    return 0
  fi

  local version_file="$_self_update_lib_dir/.installed-version"
  if [ ! -f "$version_file" ]; then
    return 0
  fi

  local source_repo installed_sha
  source_repo="$(_self_update_read_kv "$version_file" source_repo)" || return 0
  installed_sha="$(_self_update_read_kv "$version_file" installed_sha)" || return 0

  if [ -z "$source_repo" ] || ! git -C "$source_repo" rev-parse --git-dir >/dev/null 2>&1; then
    _self_update_log "recorded source_repo '$source_repo' is not a git repo - skipping"
    return 0
  fi

  if ! git -C "$source_repo" symbolic-ref -q HEAD >/dev/null; then
    _self_update_log "source repo on detached HEAD - skipping"
    return 0
  fi

  if [ -n "$(git -C "$source_repo" status --porcelain 2>/dev/null)" ]; then
    _self_update_log "source repo has uncommitted changes - skipping (resolve manually)"
    return 0
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout 10 git -C "$source_repo" fetch --quiet 2>/dev/null || {
      _self_update_log "fetch failed or timed out - skipping"
      return 0
    }
  else
    git -C "$source_repo" fetch --quiet 2>/dev/null || {
      _self_update_log "fetch failed - skipping"
      return 0
    }
  fi

  local source_sha upstream_sha
  source_sha="$(git -C "$source_repo" rev-parse HEAD 2>/dev/null)" || return 0
  upstream_sha="$(git -C "$source_repo" rev-parse '@{u}' 2>/dev/null)" || {
    _self_update_log "no upstream tracking branch - skipping"
    return 0
  }

  local source_stale=false install_stale=false
  [ "$source_sha" != "$upstream_sha" ] && source_stale=true
  [ "$installed_sha" != "$source_sha" ] && install_stale=true

  if ! $source_stale && ! $install_stale; then
    return 0
  fi

  local installed_short source_short upstream_short
  installed_short="$(_self_update_short "$installed_sha")"
  source_short="$(_self_update_short "$source_sha")"
  upstream_short="$(_self_update_short "$upstream_sha")"
  if $source_stale; then
    _self_update_log "out of date  ${installed_short} -> ${upstream_short}  (pull + reinstall)"
  else
    _self_update_log "out of date  ${installed_short} -> ${source_short}  (reinstall)"
  fi

  local answer
  if [ "${CHE_AUTO_SELF_UPDATE:-0}" = "1" ]; then
    answer=y
  else
    printf 'apply update now? [Y/n] ' >&2
    if ! IFS= read -r answer </dev/tty 2>/dev/null; then
      _self_update_log "no tty for prompt - skipping (set CHE_AUTO_SELF_UPDATE=1 to auto-apply)"
      return 0
    fi
  fi
  case "${answer:-y}" in
    n|N|no|NO) _self_update_log "skipped by user"; return 0 ;;
  esac

  if $source_stale; then
    if ! git -C "$source_repo" pull --ff-only --quiet; then
      _self_update_log "ff-only pull failed - resolve manually in $source_repo and rerun"
      return 0
    fi
  fi

  if ! _self_update_run_installer "$source_repo"; then
    _self_update_log "installer reported errors - see output above"
  fi
  return 0
}
