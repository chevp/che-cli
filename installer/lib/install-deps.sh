#!/usr/bin/env bash
# che-cli — shared dependency installer for Unix-like systems (macOS, Linux, WSL).
#
# Sourced by install.sh; can also be invoked directly:
#   bash installer/lib/install-deps.sh [--yes] [--no-ollama] [--no-model]
#
# Installs (when missing): git, curl, python3, pip, PyYAML, ollama.
# Then starts `ollama serve` in the background and pulls the default model.
#
# Flags (can be set via env or argv):
#   CHE_ASSUME_YES=1       skip all "install? [Y/n]" prompts
#   CHE_NO_DEPS=1          skip OS package installs entirely (ollama only)
#   CHE_NO_OLLAMA=1        skip ollama install + serve + model
#   CHE_NO_MODEL=1         install ollama but skip pulling the model
#   CHE_OLLAMA_MODEL=...   model to pull (default: llama3.2)

set -uo pipefail

# ---------------------------------------------------------------------------
# Defaults & flag parsing
# ---------------------------------------------------------------------------
: "${CHE_ASSUME_YES:=0}"
: "${CHE_NO_DEPS:=0}"
: "${CHE_NO_OLLAMA:=0}"
: "${CHE_NO_MODEL:=0}"
: "${CHE_OLLAMA_MODEL:=llama3.2}"
: "${CHE_OLLAMA_HOST:=http://localhost:11434}"

for arg in "$@"; do
  case "$arg" in
    -y|--yes)        CHE_ASSUME_YES=1 ;;
    --no-deps)       CHE_NO_DEPS=1 ;;
    --no-ollama)     CHE_NO_OLLAMA=1 ;;
    --no-model)      CHE_NO_MODEL=1 ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi
ok()    { printf "  ${C_GREEN}\xe2\x9c\x93${C_RESET} %s\n" "$1"; }
fail()  { printf "  ${C_RED}\xe2\x9c\x97${C_RESET} %s\n" "$1"; }
warn()  { printf "  ${C_YELLOW}!${C_RESET} %s\n" "$1"; }
info()  { printf "    ${C_DIM}%s${C_RESET}\n" "$1"; }
step()  { printf "\n${C_BOLD}${C_CYAN}==>${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$1"; }

confirm() {
  # confirm "Question text"  -> 0 (yes) / 1 (no). Defaults to yes.
  local prompt="$1" reply
  if [ "$CHE_ASSUME_YES" = "1" ] || [ ! -t 0 ]; then
    return 0
  fi
  printf "  %s [Y/n] " "$prompt"
  read -r reply || reply=""
  case "$reply" in
    n|N|no|NO) return 1 ;;
    *) return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# Platform & package-manager detection
# ---------------------------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Darwin*) echo darwin ;;
    Linux*)
      if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
        echo wsl
      else
        echo linux
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}

detect_pm() {
  # Print the package-manager name we know how to drive.
  if [ "$(detect_os)" = "darwin" ]; then
    if command -v brew >/dev/null 2>&1; then echo brew; else echo none; fi
    return
  fi
  for pm in apt-get dnf yum pacman zypper apk; do
    if command -v "$pm" >/dev/null 2>&1; then echo "$pm"; return; fi
  done
  echo none
}

CHE_OS="$(detect_os)"
CHE_PM="$(detect_pm)"

SUDO=""
if [ "$(id -u 2>/dev/null || echo 1)" != "0" ] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

# ---------------------------------------------------------------------------
# Package installation helpers
# ---------------------------------------------------------------------------
pm_refresh_done=0
pm_refresh() {
  [ "$pm_refresh_done" = "1" ] && return 0
  case "$CHE_PM" in
    apt-get) $SUDO apt-get update -y >/dev/null 2>&1 || true ;;
    dnf|yum) $SUDO "$CHE_PM" makecache -y >/dev/null 2>&1 || true ;;
    pacman)  $SUDO pacman -Sy --noconfirm >/dev/null 2>&1 || true ;;
    zypper)  $SUDO zypper --non-interactive refresh >/dev/null 2>&1 || true ;;
    apk)     $SUDO apk update >/dev/null 2>&1 || true ;;
    brew)    : ;;  # brew refreshes lazily
  esac
  pm_refresh_done=1
}

pm_install() {
  # pm_install <pkg> [pkg...]   — install one or more native packages.
  [ "$#" -eq 0 ] && return 0
  pm_refresh
  case "$CHE_PM" in
    brew)    brew install "$@" ;;
    apt-get) $SUDO apt-get install -y "$@" ;;
    dnf|yum) $SUDO "$CHE_PM" install -y "$@" ;;
    pacman)  $SUDO pacman -S --noconfirm --needed "$@" ;;
    zypper)  $SUDO zypper --non-interactive install "$@" ;;
    apk)     $SUDO apk add --no-cache "$@" ;;
    *)
      warn "no supported package manager — please install manually: $*"
      return 1
      ;;
  esac
}

# Map a logical name → distro-specific package(s).
pm_pkg_for() {
  local logical="$1"
  case "$CHE_PM:$logical" in
    brew:python)     echo python ;;
    apt-get:python)  echo "python3 python3-pip python3-venv" ;;
    dnf:python|yum:python)  echo "python3 python3-pip" ;;
    pacman:python)   echo python python-pip ;;
    zypper:python)   echo "python3 python3-pip" ;;
    apk:python)      echo "python3 py3-pip" ;;
    brew:gh)         echo gh ;;
    *:gh)            echo gh ;;
    brew:git)        echo git ;;
    *:git)           echo git ;;
    brew:curl)       echo curl ;;
    apk:curl)        echo curl ;;
    *:curl)          echo curl ;;
    *) echo "$logical" ;;
  esac
}

ensure_tool() {
  # ensure_tool <command-name> <logical-package-name> [reason]
  local cmd="$1" logical="$2" reason="${3:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd already installed"
    return 0
  fi
  if [ "$CHE_NO_DEPS" = "1" ]; then
    warn "$cmd missing (skipped: --no-deps)"
    return 1
  fi
  if [ "$CHE_PM" = "none" ]; then
    fail "$cmd missing — no supported package manager detected"
    case "$CHE_OS" in
      darwin) info "install Homebrew first: https://brew.sh" ;;
      *)      info "install $cmd manually using your distro's package manager" ;;
    esac
    return 1
  fi

  local pkgs; pkgs="$(pm_pkg_for "$logical")"
  local prompt="install $cmd"
  [ -n "$reason" ] && prompt="$prompt ($reason)"
  prompt="$prompt via $CHE_PM ($pkgs)?"

  if ! confirm "$prompt"; then
    warn "skipped $cmd install"
    return 1
  fi

  # shellcheck disable=SC2086
  if pm_install $pkgs; then
    if command -v "$cmd" >/dev/null 2>&1; then
      ok "installed $cmd"
      return 0
    fi
    warn "$pkgs installed but $cmd still not on PATH"
    return 1
  fi
  fail "failed to install $cmd"
  return 1
}

# ---------------------------------------------------------------------------
# Python + PyYAML
# ---------------------------------------------------------------------------
ensure_python() {
  step "Python (required for che workflow / che run)"
  local py=""
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c '' >/dev/null 2>&1; then
      py="$cand"; break
    fi
  done
  if [ -z "$py" ]; then
    ensure_tool python3 python "needed for che workflow / che run" || return 1
    py="python3"
  else
    ok "$py ($("$py" -c 'import sys;print(sys.version.split()[0])' 2>/dev/null))"
  fi

  if "$py" -c 'import yaml' 2>/dev/null; then
    ok "PyYAML present ($("$py" -c 'import yaml;print(yaml.__version__)' 2>/dev/null))"
    return 0
  fi
  if [ "$CHE_NO_DEPS" = "1" ]; then
    warn "PyYAML missing (skipped: --no-deps)"
    return 1
  fi
  if ! confirm "install PyYAML via pip?"; then
    warn "skipped PyYAML install"
    return 1
  fi

  # Prefer distro package on Debian/Ubuntu (PEP 668 externally-managed).
  case "$CHE_PM" in
    apt-get)
      pm_install python3-yaml >/dev/null 2>&1 && {
        ok "installed python3-yaml"; return 0;
      }
      ;;
  esac

  local pip_args="install --user pyyaml"
  # PEP 668 systems need --break-system-packages for --user installs.
  if "$py" -m pip help install 2>/dev/null | grep -q break-system-packages; then
    pip_args="install --user --break-system-packages pyyaml"
  fi
  # shellcheck disable=SC2086
  if "$py" -m pip $pip_args; then
    ok "installed PyYAML via pip --user"
    return 0
  fi
  fail "pip install pyyaml failed"
  return 1
}

# ---------------------------------------------------------------------------
# Ollama install + serve + model
# ---------------------------------------------------------------------------
ensure_ollama_binary() {
  if command -v ollama >/dev/null 2>&1; then
    ok "ollama binary present ($(ollama --version 2>/dev/null | head -n1))"
    return 0
  fi
  if [ "$CHE_NO_DEPS" = "1" ]; then
    warn "ollama missing (skipped: --no-deps)"
    return 1
  fi

  case "$CHE_OS" in
    darwin)
      if command -v brew >/dev/null 2>&1; then
        confirm "install ollama via brew?" || { warn "skipped"; return 1; }
        brew install ollama || { fail "brew install ollama failed"; return 1; }
      else
        warn "Homebrew not found — install from https://ollama.com/download/mac"
        return 1
      fi
      ;;
    linux|wsl)
      confirm "install ollama via the official installer (curl https://ollama.com/install.sh)?" \
        || { warn "skipped"; return 1; }
      if ! command -v curl >/dev/null 2>&1; then
        ensure_tool curl curl "needed to fetch the ollama installer" || return 1
      fi
      curl -fsSL https://ollama.com/install.sh | sh \
        || { fail "ollama install script failed"; return 1; }
      ;;
    *)
      warn "automatic ollama install is not supported on $CHE_OS"
      info "download manually: https://ollama.com/download"
      return 1
      ;;
  esac

  if command -v ollama >/dev/null 2>&1; then
    ok "ollama installed ($(ollama --version 2>/dev/null | head -n1))"
    return 0
  fi
  fail "ollama binary still not on PATH after install"
  return 1
}

ollama_ping() {
  curl -fsS --max-time 2 "$CHE_OLLAMA_HOST/api/tags" >/dev/null 2>&1
}

ollama_start_serve() {
  if ollama_ping; then
    ok "ollama server already reachable at $CHE_OLLAMA_HOST"
    return 0
  fi
  info "starting 'ollama serve' in the background…"
  # Detach: nohup + & so it survives the installer process.
  nohup ollama serve >/tmp/che-ollama-serve.log 2>&1 &
  disown 2>/dev/null || true

  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    if ollama_ping; then
      ok "ollama server started at $CHE_OLLAMA_HOST"
      return 0
    fi
  done
  fail "could not reach $CHE_OLLAMA_HOST after starting ollama serve"
  info "see /tmp/che-ollama-serve.log for details"
  return 1
}

ollama_pull_model() {
  if [ "$CHE_NO_MODEL" = "1" ]; then
    info "skipping model pull (--no-model)"
    return 0
  fi
  if ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx -- "$CHE_OLLAMA_MODEL\(:.*\)\{0,1\}"; then
    ok "model already present: $CHE_OLLAMA_MODEL"
    return 0
  fi
  if ! confirm "pull the default model '$CHE_OLLAMA_MODEL' (this can be a few GB)?"; then
    warn "skipped model pull"
    return 0
  fi
  if ollama pull "$CHE_OLLAMA_MODEL"; then
    ok "model pulled: $CHE_OLLAMA_MODEL"
    return 0
  fi
  fail "ollama pull $CHE_OLLAMA_MODEL failed"
  return 1
}

ensure_ollama() {
  if [ "$CHE_NO_OLLAMA" = "1" ]; then
    info "skipping ollama setup (--no-ollama)"
    return 0
  fi
  step "Ollama (default LLM provider for che commit / che ship)"
  ensure_ollama_binary || return 1
  ollama_start_serve   || return 1
  ollama_pull_model    || return 1
}

# ---------------------------------------------------------------------------
# Top-level orchestration
# ---------------------------------------------------------------------------
che_install_deps() {
  printf "${C_BOLD}che-cli — installing dependencies${C_RESET}\n"
  printf "  ${C_DIM}os: %s   pkg-manager: %s   model: %s${C_RESET}\n" \
    "$CHE_OS" "$CHE_PM" "$CHE_OLLAMA_MODEL"

  local rc=0

  step "Core shell tools (git, curl)"
  ensure_tool git  git  "che commit / che ship use git"          || rc=1
  ensure_tool curl curl "needed by ollama / openai / anthropic"  || rc=1

  ensure_python || rc=1

  # gh is optional (used by `che flow` / `che done`). Only offer if missing.
  if ! command -v gh >/dev/null 2>&1; then
    step "GitHub CLI (optional — used by 'che flow' / 'che done')"
    ensure_tool gh gh "optional, enables PR automation" || true
  fi

  ensure_ollama || rc=1

  if [ "$rc" = "0" ]; then
    printf "\n${C_GREEN}${C_BOLD}all dependencies ready${C_RESET}\n"
  else
    printf "\n${C_YELLOW}${C_BOLD}some dependencies were skipped or failed${C_RESET}\n"
    printf "  ${C_DIM}run 'che doctor' afterwards to see what's still missing${C_RESET}\n"
  fi
  return $rc
}

# Allow direct invocation without sourcing.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  che_install_deps
  exit $?
fi
