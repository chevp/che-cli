#!/usr/bin/env bash
# Verifies git is installed.

CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CHECK_DIR/platform.sh"

type ok   >/dev/null 2>&1 || ok()   { printf "  ✓ %s\n" "$1"; }
type fail >/dev/null 2>&1 || fail() { printf "  ✗ %s\n" "$1"; }
type info >/dev/null 2>&1 || info() { printf "    %s\n" "$1"; }

git_install_hint() {
  case "$CHE_OS" in
    darwin)    info "install: brew install git" ;;
    windows)   info "install: https://git-scm.com/download/win" ;;
    wsl|linux) info "install: sudo apt-get install git  (or your distro equivalent)" ;;
    *)         info "install: https://git-scm.com/downloads" ;;
  esac
}

git_check() {
  if command -v git >/dev/null 2>&1; then
    ok "git $(git --version | awk '{print $3}')"
    return 0
  fi
  fail "git not installed"
  git_install_hint
  return 1
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "git:"
  git_check
fi
