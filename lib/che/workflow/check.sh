#!/usr/bin/env bash
# Verifies that Python + PyYAML are available (used by `che workflow` / `che run`).

CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CHECK_DIR/platform.sh"

type ok   >/dev/null 2>&1 || ok()   { printf "  %s\n" "$1"; }
type fail >/dev/null 2>&1 || fail() { printf "  error: %s\n" "$1"; }
type info >/dev/null 2>&1 || info() { printf "  hint: %s\n" "$1"; }

pyyaml_install_hint() {
  case "$CHE_OS" in
    darwin)    info "install: pip3 install pyyaml" ;;
    windows)   info "install: pip install pyyaml" ;;
    wsl|linux) info "install: pip3 install pyyaml  (or: apt install python3-yaml)" ;;
    *)         info "install: pip install pyyaml" ;;
  esac
}

python_install_hint() {
  case "$CHE_OS" in
    darwin)    info "install: brew install python" ;;
    windows)   info "install: winget install --id Python.Python.3.12" ;;
    wsl|linux) info "install: apt install python3 python3-pip" ;;
    *)         info "see https://www.python.org/downloads/" ;;
  esac
}

workflow_check() {
  local rc=0 py="" cand
  # Probe by actually running each candidate — on Windows, `python3` is often
  # a Store App Execution Alias that's on PATH but doesn't execute.
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c '' >/dev/null 2>&1; then
      py="$cand"; break
    fi
  done

  if [ -z "$py" ]; then
    fail "python3 not installed (required for che workflow / che run)"
    python_install_hint
    return 1
  fi

  local pyver; pyver="$("$py" -c 'import sys;print(sys.version.split()[0])' 2>/dev/null)"
  ok "$py $pyver"

  if "$py" -c 'import yaml' 2>/dev/null; then
    local yamlver
    yamlver="$("$py" -c 'import yaml;print(yaml.__version__)' 2>/dev/null)"
    ok "PyYAML $yamlver"
  else
    fail "PyYAML not installed (required for che workflow / che run)"
    pyyaml_install_hint
    rc=1
  fi
  return $rc
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "workflow:"
  workflow_check
fi
