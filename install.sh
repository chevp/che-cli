#!/usr/bin/env bash
# che-cli installer for macOS / Linux / WSL.
#
# Beyond just copying files, this installer can also bring in every runtime
# dependency che needs (git, curl, python3, PyYAML, ollama, default model).
#
# Usage:
#   ./install.sh                  # interactive — asks before each install
#   ./install.sh --yes            # unattended — say yes to everything
#   ./install.sh --no-deps        # skip OS-level package installs
#   ./install.sh --no-ollama      # don't install ollama / start serve / pull model
#   ./install.sh --no-model       # install ollama but skip the model pull
#   ./install.sh --no-path-edit   # don't touch your shell rc
#   PREFIX=/usr/local ./install.sh
#
# Env-var equivalents (so this can be driven from CI):
#   CHE_ASSUME_YES=1, CHE_NO_DEPS=1, CHE_NO_OLLAMA=1, CHE_NO_MODEL=1,
#   CHE_NO_PATH_EDIT=1, CHE_OLLAMA_MODEL=...

set -uo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Translate CLI flags to env vars for install-deps.sh.
for arg in "$@"; do
  case "$arg" in
    -y|--yes)         export CHE_ASSUME_YES=1 ;;
    --no-deps)        export CHE_NO_DEPS=1 ;;
    --no-ollama)      export CHE_NO_OLLAMA=1 ;;
    --no-model)       export CHE_NO_MODEL=1 ;;
    --no-path-edit)   export CHE_NO_PATH_EDIT=1 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "install.sh: unknown flag '$arg'" >&2
      echo "run with --help to see options" >&2
      exit 2
      ;;
  esac
done

if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_CYAN=""; C_BOLD=""; C_DIM=""; C_RESET=""
fi

printf "${C_BOLD}che-cli install${C_RESET}  ${C_DIM}(prefix: %s)${C_RESET}\n" "$PREFIX"

# ---------------------------------------------------------------------------
# 1. Copy the dispatcher + lib tree into PREFIX.
# ---------------------------------------------------------------------------
printf "\n${C_BOLD}${C_CYAN}==>${C_RESET} ${C_BOLD}Installing files${C_RESET}\n"

mkdir -p "$PREFIX/bin" "$PREFIX/lib/che"
install -m 0755 "$SRC/bin/che" "$PREFIX/bin/che"
cp -R "$SRC/lib/che/." "$PREFIX/lib/che/"
find "$PREFIX/lib/che" -name "*.sh" -exec chmod 0755 {} +

printf "  ${C_GREEN}\xe2\x9c\x93${C_RESET} %s\n" "$PREFIX/bin/che"
printf "  ${C_GREEN}\xe2\x9c\x93${C_RESET} %s\n" "$PREFIX/lib/che/  (full tree)"

# ---------------------------------------------------------------------------
# 2. Install runtime dependencies (git, python, ollama, etc.).
# ---------------------------------------------------------------------------
DEPS_SCRIPT="$SRC/installer/lib/install-deps.sh"
if [ -f "$DEPS_SCRIPT" ]; then
  # Make ollama visible to install-deps via PATH (in case PREFIX/bin was just added).
  export PATH="$PREFIX/bin:$PATH"
  bash "$DEPS_SCRIPT" || true
else
  printf "\n${C_DIM}(installer/lib/install-deps.sh not found — skipping dependency install)${C_RESET}\n"
fi

# ---------------------------------------------------------------------------
# 3. PATH wiring.
# ---------------------------------------------------------------------------
printf "\n${C_BOLD}${C_CYAN}==>${C_RESET} ${C_BOLD}PATH${C_RESET}\n"

shell_rc=""
case "$(basename "${SHELL:-}")" in
  zsh)  shell_rc="$HOME/.zshrc" ;;
  bash)
    if [ "$(uname -s)" = "Darwin" ] && [ -f "$HOME/.bash_profile" ]; then
      shell_rc="$HOME/.bash_profile"
    else
      shell_rc="$HOME/.bashrc"
    fi
    ;;
  fish) shell_rc="$HOME/.config/fish/config.fish" ;;
esac

export_line="export PATH=\"$PREFIX/bin:\$PATH\""
[ "$(basename "${SHELL:-}")" = "fish" ] \
  && export_line="set -gx PATH $PREFIX/bin \$PATH"

case ":$PATH:" in
  *":$PREFIX/bin:"*)
    printf "  ${C_GREEN}\xe2\x9c\x93${C_RESET} %s already on PATH\n" "$PREFIX/bin"
    ;;
  *)
    if [ -n "$shell_rc" ] && [ "${CHE_NO_PATH_EDIT:-0}" != "1" ]; then
      mkdir -p "$(dirname "$shell_rc")"
      touch "$shell_rc"
      if ! grep -Fqs "$export_line" "$shell_rc"; then
        {
          echo ""
          echo "# added by che-cli install.sh"
          echo "$export_line"
        } >> "$shell_rc"
        printf "  ${C_GREEN}\xe2\x9c\x93${C_RESET} added %s to PATH in %s\n" "$PREFIX/bin" "$shell_rc"
      else
        printf "  ${C_GREEN}\xe2\x9c\x93${C_RESET} PATH export already in %s\n" "$shell_rc"
      fi
      printf "  ${C_DIM}open a new terminal (or: source %s)${C_RESET}\n" "$shell_rc"
    else
      printf "  add to your shell rc:\n    %s\n" "$export_line"
    fi
    ;;
esac

# ---------------------------------------------------------------------------
# 4. Final verification.
# ---------------------------------------------------------------------------
printf "\n${C_BOLD}${C_CYAN}==>${C_RESET} ${C_BOLD}Verification${C_RESET}\n"
if [ -x "$PREFIX/bin/che" ]; then
  PATH="$PREFIX/bin:$PATH" "$PREFIX/bin/che" doctor || true
fi

printf "\n${C_BOLD}${C_GREEN}done.${C_RESET} try: ${C_BOLD}che commit${C_RESET}\n"
