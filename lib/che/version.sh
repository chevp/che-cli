#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version_file="$LIB_DIR/.installed-version"

read_kv() {
  local file="$1" key="$2" line
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "$key="*) printf '%s\n' "${line#"$key="}"; return 0 ;;
    esac
  done < "$file"
  return 1
}

installed_describe="$(read_kv "$version_file" installed_describe 2>/dev/null || true)"
installed_sha="$(read_kv "$version_file" installed_sha 2>/dev/null || true)"
source_repo="$(read_kv "$version_file" source_repo 2>/dev/null || true)"
installed_at="$(read_kv "$version_file" installed_at 2>/dev/null || true)"

if [ -z "$installed_describe" ] && git -C "$LIB_DIR/../.." rev-parse --git-dir >/dev/null 2>&1; then
  installed_describe="$(git -C "$LIB_DIR/../.." describe --tags --always --dirty 2>/dev/null || true)"
  installed_sha="$(git -C "$LIB_DIR/../.." rev-parse HEAD 2>/dev/null || true)"
fi

printf 'che-cli'
[ -n "$installed_describe" ] && printf ' %s' "$installed_describe"
printf '\n'
[ -n "$installed_sha" ] && printf 'sha: %s\n' "$installed_sha"
[ -n "$source_repo" ] && printf 'source: %s\n' "$source_repo"
[ -n "$installed_at" ] && printf 'installed_at: %s\n' "$installed_at"
