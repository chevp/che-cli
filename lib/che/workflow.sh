#!/usr/bin/env bash
# che workflow — sub-dispatcher for list / show / run.
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
che workflow — manage and run scripted workflows from .che/workflows/*.yml

Usage: che workflow <subcommand> [args]

Subcommands:
  list                       list workflows in the current repo
  show <name>                print the parsed plan of a workflow
  run  <name> [--k=v ...]    execute a workflow (also: che run <name>)

A workflow is a YAML manifest that references existing scripts. Each step
declares 'script:' (an executable path relative to the workflow root) and
optional 'args:' with \${input} substitution. No inline bash.

Docs:    https://chevp.github.io/che-cli/workflow.html
Doctor:  che doctor workflow   (verifies yq is installed)
EOF
}

sub="${1:-}"
[ "$#" -gt 0 ] && shift || true

case "$sub" in
  list)           exec bash "$LIB_DIR/workflow/list.sh" "$@" ;;
  show)           exec bash "$LIB_DIR/workflow/show.sh" "$@" ;;
  run)            exec bash "$LIB_DIR/workflow/run.sh"  "$@" ;;
  ""|-h|--help)   usage ;;
  *)
    echo "che workflow: unknown subcommand '$sub'" >&2
    usage >&2
    exit 1
    ;;
esac
