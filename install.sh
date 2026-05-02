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
#   CHE_VERBOSE=1   restore per-item ✓ output (default is compact)

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

# ---------------------------------------------------------------------------
# 1. Copy the dispatcher + lib tree into PREFIX. (silent on success)
# ---------------------------------------------------------------------------
mkdir -p "$PREFIX/bin" "$PREFIX/lib/che"
install -m 0755 "$SRC/bin/che" "$PREFIX/bin/che"
cp -R "$SRC/lib/che/." "$PREFIX/lib/che/"
find "$PREFIX/lib/che" -name "*.sh" -exec chmod 0755 {} +

# Pin the install to the source repo's exact commit. `che ship` reads this
# file to decide whether the running install is stale (see lib/che/self_update.sh).
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  _installed_sha="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || printf unknown)"
  _installed_describe="$(git -C "$SRC" describe --tags --always --dirty 2>/dev/null || printf unknown)"
else
  _installed_sha=unknown
  _installed_describe=unknown
fi
{
  printf 'source_repo=%s\n'        "$SRC"
  printf 'installed_sha=%s\n'      "$_installed_sha"
  printf 'installed_describe=%s\n' "$_installed_describe"
  printf 'installed_at=%s\n'       "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%s)"
} > "$PREFIX/lib/che/.installed-version"

# Compact header: name + path + short SHA in one line.
_short_sha="${_installed_sha:0:7}"
[ -z "$_short_sha" ] && _short_sha="unknown"
printf "${C_BOLD}che-cli installed${C_RESET} → %s  ${C_DIM}(%s)${C_RESET}\n" \
  "$PREFIX/bin/che" "$_short_sha"
unset _installed_sha _installed_describe _short_sha

# ---------------------------------------------------------------------------
# 2. Install runtime dependencies (git, python, ollama, etc.).
# ---------------------------------------------------------------------------
DEPS_SCRIPT="$SRC/installer/lib/install-deps.sh"
if [ -f "$DEPS_SCRIPT" ]; then
  # Make ollama visible to install-deps via PATH (in case PREFIX/bin was just added).
  export PATH="$PREFIX/bin:$PATH"
  bash "$DEPS_SCRIPT" || true
else
  printf "${C_DIM}(installer/lib/install-deps.sh not found — skipping dependency install)${C_RESET}\n"
fi

# ---------------------------------------------------------------------------
# 3. PATH wiring. Silent if already on PATH; otherwise prints the one action taken.
# ---------------------------------------------------------------------------
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
  *":$PREFIX/bin:"*) : ;;  # already on PATH — no message
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
        printf "${C_DIM}path     ${C_RESET}+ %s in %s ${C_DIM}(open a new terminal)${C_RESET}\n" \
          "$PREFIX/bin" "$shell_rc"
      fi
    else
      printf "${C_DIM}path     ${C_RESET}add to your shell rc:  %s\n" "$export_line"
    fi
    ;;
esac

# ---------------------------------------------------------------------------
# 4. Final verification (compact). doctor prints its own summary lines.
# ---------------------------------------------------------------------------
if [ -x "$PREFIX/bin/che" ]; then
  PATH="$PREFIX/bin:$PATH" "$PREFIX/bin/che" doctor || true
fi

printf "${C_GREEN}→ ready.${C_RESET}  next: ${C_BOLD}che commit${C_RESET}\n"