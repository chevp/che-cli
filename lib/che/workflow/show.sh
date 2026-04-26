#!/usr/bin/env bash
# che workflow show <name> — print the normalized step plan of a workflow.
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/loader.sh"

case "${1:-}" in
  -h|--help|"")
    cat <<EOF
che workflow show — print the parsed plan of a workflow.

Usage: che workflow show <name>

Validates the file shape, then prints name, description, declared inputs,
and each step as it would be executed.
EOF
    [ -z "${1:-}" ] && exit 1 || exit 0
    ;;
esac

name="$1"; shift || true
[ "$#" -eq 0 ] || wf_die "show: unexpected extra arguments"

wf_require_yq
file="$(wf_resolve_file "$name")"
wf_validate "$file"

printf '%sname%s        %s\n'        "$WF_C_BOLD" "$WF_C_RESET" "$(wf_yq '.name' "$file")"
desc="$(wf_yq '.description' "$file")"
[ -n "$desc" ] && printf '%sdescription%s %s\n' "$WF_C_BOLD" "$WF_C_RESET" "$desc"
printf '%sfile%s        %s\n'        "$WF_C_BOLD" "$WF_C_RESET" "$file"
printf '%sroot%s        %s\n'        "$WF_C_BOLD" "$WF_C_RESET" "$WF_ROOT"

inputs_len="$(wf_yq '.inputs | length' "$file")"
if [ "${inputs_len:-0}" -gt 0 ]; then
  printf '\n%sinputs%s\n' "$WF_C_BOLD" "$WF_C_RESET"
  for ((i = 0; i < inputs_len; i++)); do
    iname="$(wf_yq ".inputs[$i].name" "$file")"
    ireq="$(wf_yq "(.inputs[$i].required) // false" "$file")"
    idesc="$(wf_yq ".inputs[$i].description" "$file")"
    tag="optional"
    [ "$ireq" = "true" ] && tag="required"
    if [ -n "$idesc" ]; then
      printf '  - %s  (%s)  %s%s%s\n' "$iname" "$tag" "$WF_C_DIM" "$idesc" "$WF_C_RESET"
    else
      printf '  - %s  (%s)\n' "$iname" "$tag"
    fi
  done
fi

steps_len="$(wf_yq '.steps | length' "$file")"
printf '\n%ssteps%s\n' "$WF_C_BOLD" "$WF_C_RESET"
for ((i = 0; i < steps_len; i++)); do
  sname="$(wf_yq ".steps[$i].name" "$file")"
  script="$(wf_yq ".steps[$i].script" "$file")"
  [ -n "$sname" ] || sname="(unnamed)"
  printf '  %d. %s\n' $((i + 1)) "$sname"
  printf '     %sscript%s %s\n' "$WF_C_DIM" "$WF_C_RESET" "$script"
  args_len="$(wf_yq ".steps[$i].args | length" "$file")"
  if [ "${args_len:-0}" -gt 0 ]; then
    printf '     %sargs%s   ' "$WF_C_DIM" "$WF_C_RESET"
    for ((j = 0; j < args_len; j++)); do
      a="$(wf_yq ".steps[$i].args[$j]" "$file")"
      printf '%q ' "$a"
    done
    printf '\n'
  fi
done
