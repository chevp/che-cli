#!/usr/bin/env bash
# che-cli installer for macOS / Linux / WSL.
#
# Runs `npm install` (which fetches and builds the chi dep), then symlinks
# bin/che into PREFIX/bin so that `che` is available on PATH.
#
# Usage:
#   ./install.sh                   # interactive
#   ./install.sh --no-path-edit    # don't touch your shell rc
#   PREFIX=/usr/local ./install.sh
#
# Requires: node 20+, npm.
#
# Tip: easier install path — `npm install -g github:chevp/che-cli`.

set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
CHE_NO_PATH_EDIT="${CHE_NO_PATH_EDIT:-0}"

for arg in "$@"; do
  case "$arg" in
    -y|--yes)        : ;;
    --no-path-edit)  CHE_NO_PATH_EDIT=1 ;;
    -h|--help)       sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)               echo "install.sh: unknown flag '$arg'" >&2; exit 2 ;;
  esac
done

command -v node >/dev/null 2>&1 || { echo "error: node not found — che requires Node.js 20+" >&2; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "error: npm not on PATH" >&2; exit 1; }

node_major="$(node -e 'process.stdout.write(String(process.versions.node.split(".")[0]))')"
[ "$node_major" -lt 20 ] 2>/dev/null && { echo "error: node $node_major found, che requires node 20+" >&2; exit 1; }

echo "che-cli install"
echo "  source: $SRC"
echo "  prefix: $PREFIX"

(cd "$SRC" && npm install --no-audit --no-fund) || { echo "error: npm install failed" >&2; exit 1; }

mkdir -p "$PREFIX/bin"
ln -sf "$SRC/bin/che" "$PREFIX/bin/che"

shell_rc=""
case "$(basename "${SHELL:-}")" in
  zsh)  shell_rc="$HOME/.zshrc" ;;
  bash)
    if [ "$(uname -s)" = "Darwin" ] && [ -f "$HOME/.bash_profile" ]; then
      shell_rc="$HOME/.bash_profile"
    else
      shell_rc="$HOME/.bashrc"
    fi ;;
  fish) shell_rc="$HOME/.config/fish/config.fish" ;;
esac

export_line="export PATH=\"$PREFIX/bin:\$PATH\""
[ "$(basename "${SHELL:-}")" = "fish" ] && export_line="set -gx PATH $PREFIX/bin \$PATH"

case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *)
    if [ -n "$shell_rc" ] && [ "$CHE_NO_PATH_EDIT" != "1" ]; then
      mkdir -p "$(dirname "$shell_rc")"
      touch "$shell_rc"
      if ! grep -Fqs "$export_line" "$shell_rc"; then
        printf "\n# added by che-cli install.sh\n%s\n" "$export_line" >> "$shell_rc"
        echo "  path  + $PREFIX/bin in $shell_rc (open a new terminal)"
      fi
    else
      echo "  path  add to your shell rc:  $export_line"
    fi ;;
esac

echo "→ ready. next: che status"
