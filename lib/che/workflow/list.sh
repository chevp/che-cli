#!/usr/bin/env bash
# che workflow list — print all workflows discovered under <repo>/.che/workflow/.
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/loader.sh"

case "${1:-}" in
  -h|--help)
    cat <<EOF
che workflow list — print all workflows in this repo.

Usage: che workflow list

Discovers .che/workflows/ by walking up from \$PWD and lists every *.yml /
*.yaml file inside, with its declared description.

Docs: https://chevp.github.io/che-cli/workflow.html
EOF
    exit 0
    ;;
  "") ;;
  *) wf_die "list: unexpected argument '$1'" ;;
esac

wf_require_yq
wf_find_dir || wf_die "no .che/workflow/ found above $PWD"

shopt -s nullglob
files=("$WF_DIR"/*.yml "$WF_DIR"/*.yaml)
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
  echo "no workflows in $WF_DIR" >&2
  exit 0
fi

printf '%s\n' "$WF_DIR"
for f in "${files[@]}"; do
  base="$(basename "$f")"
  name="${base%.*}"
  desc="$(wf_yq '.description' "$f")"
  if [ -n "$desc" ]; then
    printf '  %s%s%s — %s\n' "$WF_C_BOLD" "$name" "$WF_C_RESET" "$desc"
  else
    printf '  %s%s%s\n' "$WF_C_BOLD" "$name" "$WF_C_RESET"
  fi
done
