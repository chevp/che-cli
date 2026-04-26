#!/usr/bin/env bash
# che reinstall — re-run the current repo's reinstall script.
# Convention: the repo provides scripts/reinstall.sh (or scripts/reinstall.ps1).
set -euo pipefail

usage() {
  cat <<EOF
che reinstall — re-run the current repo's reinstall script.

Usage: che reinstall [--] [args...]

Looks for the repo-local reinstall script (in order):
  ./scripts/reinstall.sh           (cwd, macOS/Linux)
  <git-root>/scripts/reinstall.sh  (macOS/Linux)
  ./scripts/reinstall.ps1          (cwd, Windows via pwsh)
  <git-root>/scripts/reinstall.ps1 (Windows via pwsh)

Any extra args are forwarded to the script.
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

candidates=(
  "./scripts/reinstall.sh"
  "${git_root:+$git_root/scripts/reinstall.sh}"
  "./scripts/reinstall.ps1"
  "${git_root:+$git_root/scripts/reinstall.ps1}"
)

for path in "${candidates[@]}"; do
  [ -z "$path" ] && continue
  [ -f "$path" ] || continue
  case "$path" in
    *.ps1)
      if ! command -v pwsh >/dev/null 2>&1; then
        echo "che reinstall: found $path but pwsh is not installed" >&2
        exit 1
      fi
      exec pwsh -File "$path" "$@"
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