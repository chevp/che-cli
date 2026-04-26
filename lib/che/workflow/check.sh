#!/usr/bin/env bash
# Verifies that yq (mikefarah Go variant) is installed.

CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CHECK_DIR/platform.sh"

type ok   >/dev/null 2>&1 || ok()   { printf "  ✓ %s\n" "$1"; }
type fail >/dev/null 2>&1 || fail() { printf "  ✗ %s\n" "$1"; }
type info >/dev/null 2>&1 || info() { printf "    %s\n" "$1"; }

yq_install_hint() {
  case "$CHE_OS" in
    darwin)    info "install: brew install yq" ;;
    windows)   info "install: winget install --id MikeFarah.yq" ;;
    wsl|linux) info "install: see https://github.com/mikefarah/yq#install" ;;
    *)         info "install: https://github.com/mikefarah/yq" ;;
  esac
}

workflow_check() {
  local rc=0
  if command -v yq >/dev/null 2>&1; then
    local v; v="$(yq --version 2>&1 | head -n1)"
    if echo "$v" | grep -qi 'mikefarah\|version v\?[34]'; then
      ok "yq ($v)"
    else
      fail "yq found but not the mikefarah/yq Go binary"
      info "current: $v"
      info "che workflow needs the Go variant (different expression language)"
      yq_install_hint
      rc=1
    fi
  else
    fail "yq not installed (required for che workflow / che run)"
    yq_install_hint
    rc=1
  fi
  return $rc
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "workflow:"
  workflow_check
fi
