#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$PREFIX/bin" "$PREFIX/lib/che"

install -m 0755 "$SRC/bin/che" "$PREFIX/bin/che"

# Mirror the lib tree (preserves subfolders: client/, git/, ollama/, docker/).
cp -R "$SRC/lib/che/." "$PREFIX/lib/che/"
find "$PREFIX/lib/che" -name "*.sh" -exec chmod 0755 {} +

echo "installed:"
echo "  $PREFIX/bin/che"
echo "  $PREFIX/lib/che/  (full tree)"
echo
case ":$PATH:" in
  *":$PREFIX/bin:"*)
    echo "PATH is set up — try: che doctor"
    ;;
  *)
    echo "add to your shell rc:"
    echo "  export PATH=\"$PREFIX/bin:\$PATH\""
    ;;
esac
echo
echo "On Windows, run this from Git Bash or WSL."
