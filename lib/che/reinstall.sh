#!/usr/bin/env bash
# che reinstall — re-run the current repo's reinstall script, or fall back
# to reinstalling che itself when the current repo doesn't provide one.
# Convention: a repo provides scripts/reinstall.sh (or scripts/reinstall.ps1).
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/platform.sh"

usage() {
  cat <<EOF
che reinstall — re-run the current repo's reinstall script, or reinstall
che itself if the current repo doesn't have one.

Usage: che reinstall [--self] [--] [args...]

Looks for the repo-local reinstall script. On Windows, the .ps1 form is
preferred (so installer flags like -NoDeps work and the install prefix
matches the PowerShell installer's default \$env:LOCALAPPDATA\\che).
Elsewhere, the .sh form is preferred.

  windows: scripts/reinstall.ps1 → scripts/reinstall.sh
  other:   scripts/reinstall.sh  → scripts/reinstall.ps1

Both are searched in the cwd first, then at the git root. If neither
exists, falls back to reinstalling che itself from the source repo
recorded in <prefix>/lib/che/.installed-version.

  --self    skip the per-repo lookup; always reinstall che itself.

Any extra args are forwarded to the chosen script.
EOF
}

self_only=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --self)    self_only=1; shift ;;
  --)        shift ;;
esac

# Reinstall che-cli itself by invoking the source repo's installer. Used as
# a fallback when no per-repo reinstall script is found, and unconditionally
# when --self is passed.
reinstall_che_self() {
  local version_file="$LIB_DIR/.installed-version" source_repo="" line
  if [ -f "$version_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      case "$line" in
        source_repo=*) source_repo="${line#source_repo=}" ;;
      esac
    done < "$version_file"
  fi

  if [ -z "$source_repo" ] || [ ! -d "$source_repo" ]; then
    echo "che reinstall: cannot locate che-cli source repo (missing or invalid $version_file)" >&2
    echo "  reinstall manually from your che-cli clone: bash install.sh" >&2
    exit 1
  fi

  if [ "$CHE_OS" = "windows" ] && [ -f "$source_repo/install.ps1" ]; then
    if command -v pwsh >/dev/null 2>&1; then
      exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$source_repo/install.ps1" "$@"
    elif command -v powershell >/dev/null 2>&1; then
      exec powershell -NoProfile -ExecutionPolicy Bypass -File "$source_repo/install.ps1" "$@"
    fi
  fi

  if [ -f "$source_repo/install.sh" ]; then
    exec bash "$source_repo/install.sh" "$@"
  fi

  echo "che reinstall: no installer found in $source_repo (tried install.sh, install.ps1)" >&2
  exit 1
}

if [ "$self_only" = "1" ]; then
  reinstall_che_self "$@"
fi

git_root=""
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  git_root="$(git rev-parse --show-toplevel)"
fi

if [ "$CHE_OS" = "windows" ]; then
  candidates=(
    "./scripts/reinstall.ps1"
    "${git_root:+$git_root/scripts/reinstall.ps1}"
    "./scripts/reinstall.sh"
    "${git_root:+$git_root/scripts/reinstall.sh}"
  )
else
  candidates=(
    "./scripts/reinstall.sh"
    "${git_root:+$git_root/scripts/reinstall.sh}"
    "./scripts/reinstall.ps1"
    "${git_root:+$git_root/scripts/reinstall.ps1}"
  )
fi

for path in "${candidates[@]}"; do
  [ -z "$path" ] && continue
  [ -f "$path" ] || continue
  case "$path" in
    *.ps1)
      # Prefer PowerShell Core (pwsh, 7+); fall back to Windows PowerShell
      # (powershell.exe, 5.1) which ships with every Windows install.
      if command -v pwsh >/dev/null 2>&1; then
        exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$path" "$@"
      elif command -v powershell >/dev/null 2>&1; then
        exec powershell -NoProfile -ExecutionPolicy Bypass -File "$path" "$@"
      else
        echo "che reinstall: found $path but no PowerShell available" >&2
        echo "  install pwsh: winget install Microsoft.PowerShell" >&2
        exit 1
      fi
      ;;
    *)
      if [ -x "$path" ]; then
        exec "$path" "$@"
      else
        exec bash "$path" "$@"
      fi
      ;;
  esac
done

# No per-repo reinstall script — fall back to reinstalling che itself.
searched="$(pwd)"
if [ -n "$git_root" ] && [ "$git_root" != "$(pwd)" ]; then
  searched="$searched or $git_root"
fi
echo "che reinstall: no scripts/reinstall.sh in $searched — reinstalling che itself" >&2
reinstall_che_self "$@"