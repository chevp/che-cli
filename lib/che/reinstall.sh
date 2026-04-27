#!/usr/bin/env bash
# che reinstall — re-run the current repo's reinstall script.
# Convention: the repo provides scripts/reinstall.sh (or scripts/reinstall.ps1).
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/platform.sh"

usage() {
  cat <<EOF
che reinstall — re-run the current repo's reinstall script.

Usage: che reinstall [--] [args...]

Looks for the repo-local reinstall script. On Windows, the .ps1 form is
preferred (so installer flags like -NoDeps work and the install prefix
matches the PowerShell installer's default \$env:LOCALAPPDATA\\che).
Elsewhere, the .sh form is preferred.

  windows: scripts/reinstall.ps1 → scripts/reinstall.sh
  other:   scripts/reinstall.sh  → scripts/reinstall.ps1

Both are searched in the cwd first, then at the git root.
Any extra args are forwarded to the chosen script.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --)        shift ;;
esac

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

echo "che reinstall: no scripts/reinstall.sh found in $(pwd)${git_root:+ or $git_root}" >&2
echo "Convention: each repo provides its own scripts/reinstall.sh." >&2
exit 1