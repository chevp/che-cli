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

# Pick a shell rc file based on the user's login shell.
shell_rc=""
case "$(basename "${SHELL:-}")" in
  zsh)  shell_rc="$HOME/.zshrc" ;;
  bash)
    # macOS bash reads .bash_profile for login shells; Linux uses .bashrc.
    if [ "$(uname -s)" = "Darwin" ] && [ -f "$HOME/.bash_profile" ]; then
      shell_rc="$HOME/.bash_profile"
    else
      shell_rc="$HOME/.bashrc"
    fi
    ;;
esac

export_line="export PATH=\"$PREFIX/bin:\$PATH\""

case ":$PATH:" in
  *":$PREFIX/bin:"*)
    echo "PATH is set up — try: che doctor"
    ;;
  *)
    if [ -n "$shell_rc" ] && [ "${CHE_NO_PATH_EDIT:-0}" != "1" ]; then
      touch "$shell_rc"
      if ! grep -Fqs "$export_line" "$shell_rc"; then
        {
          echo ""
          echo "# added by che-cli install.sh"
          echo "$export_line"
        } >> "$shell_rc"
        echo "added $PREFIX/bin to PATH in $shell_rc"
      else
        echo "$shell_rc already contains the PATH export"
      fi
      echo "open a new terminal (or: source $shell_rc), then run: che doctor"
    else
      echo "add to your shell rc:"
      echo "  $export_line"
    fi
    ;;
esac
echo
echo "On Windows, run this from Git Bash or WSL."
