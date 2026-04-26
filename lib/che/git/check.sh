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

gh_install_hint() {
  case "$CHE_OS" in
    darwin)    info "install: brew install gh" ;;
    windows)   info "install: winget install --id GitHub.cli" ;;
    wsl|linux) info "install: see https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
    *)         info "install: https://cli.github.com/" ;;
  esac
  info "docs:    https://cli.github.com/manual/"
}

git_check() {
  local rc=0
  if command -v git >/dev/null 2>&1; then
    ok "git $(git --version | awk '{print $3}')"
  else
    fail "git not installed"
    git_install_hint
    rc=1
  fi

  if command -v gh >/dev/null 2>&1; then
    ok "gh $(gh --version | awk 'NR==1{print $3}')  (required for che flow / che done)"
    if gh auth status >/dev/null 2>&1; then
      ok "gh authenticated"
    else
      fail "gh not authenticated"
      info "run: gh auth login"
      rc=1
    fi
  else
    fail "gh not installed  (required for che flow / che done)"
    gh_install_hint
    rc=1
  fi

  return $rc
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "git:"
  git_check
fi
