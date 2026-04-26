#!/usr/bin/env bash
# che workflow run <name> [--key=value ...] — execute a workflow's steps.
#
# Steps run sequentially, fail-fast, with the workflow root as CWD. Each step
# is a separate `bash <script> <substituted-args...>` invocation, so step
# scripts stay independently runnable.
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_DIR/loader.sh"

usage() {
  cat <<EOF
che workflow run — execute a workflow's steps.

Usage:
  che workflow run <name> [--key=value ...]
  che run <name> [--key=value ...]      (alias)

Inputs declared in the workflow file are passed via --key=value flags and
substituted into args as \${key}. Required inputs that are missing abort
the run before any step starts.

Options:
  --dry-run    print the step plan with substituted args; do not exec
  -h, --help   show this help
EOF
}

declare -A WF_INPUTS=()
dry=false
name=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) dry=true ;;
    --*=*)
      kv="${1#--}"
      k="${kv%%=*}"
      v="${kv#*=}"
      [ -n "$k" ] || wf_die "empty --key in '$1'"
      WF_INPUTS["$k"]="$v"
      ;;
    --*)
      k="${1#--}"
      shift
      [ "$#" -gt 0 ] || wf_die "missing value for --$k"
      WF_INPUTS["$k"]="$1"
      ;;
    -*) wf_die "unknown option '$1'" ;;
    *)
      [ -z "$name" ] || wf_die "only one workflow name accepted (got '$name' and '$1')"
      name="$1"
      ;;
  esac
  shift
done

[ -n "$name" ] || { usage >&2; exit 1; }

wf_require_yq
file="$(wf_resolve_file "$name")"
wf_validate "$file"

# Verify required inputs are present.
missing=()
while IFS= read -r in_name; do
  [ -n "$in_name" ] || continue
  if [ "$(wf_input_required "$file" "$in_name")" = "1" ] \
     && [ -z "${WF_INPUTS[$in_name]+x}" ]; then
    missing+=("$in_name")
  fi
done < <(wf_input_names "$file")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "che workflow: missing required input(s): ${missing[*]}" >&2
  echo "  pass them as --${missing[0]}=value" >&2
  exit 1
fi

steps_len="$(wf_yq '.steps | length' "$file")"
printf '%s── workflow: %s ──%s\n' "$WF_C_BOLD" "$(wf_yq '.name' "$file")" "$WF_C_RESET"
printf '%sroot%s %s\n' "$WF_C_DIM" "$WF_C_RESET" "$WF_ROOT"

cd "$WF_ROOT"

for ((i = 0; i < steps_len; i++)); do
  sname="$(wf_yq ".steps[$i].name" "$file")"
  script="$(wf_yq ".steps[$i].script" "$file")"
  [ -n "$sname" ] || sname="step $((i + 1))"

  # Substitute inputs into script path itself (rare but useful) and each arg.
  script="$(wf_substitute "$script")"

  args=()
  args_len="$(wf_yq ".steps[$i].args | length" "$file")"
  if [ "${args_len:-0}" -gt 0 ]; then
    for ((j = 0; j < args_len; j++)); do
      raw="$(wf_yq ".steps[$i].args[$j]" "$file")"
      args+=("$(wf_substitute "$raw")")
    done
  fi

  printf '\n%s▶ [%d/%d] %s%s\n' \
    "$WF_C_BOLD" $((i + 1)) "$steps_len" "$sname" "$WF_C_RESET"
  printf '%s  %s' "$WF_C_DIM" "$script"
  for a in "${args[@]}"; do printf ' %q' "$a"; done
  printf '%s\n' "$WF_C_RESET"

  if [ "$dry" = true ]; then continue; fi

  if [ ! -f "$script" ]; then
    printf '%s  ✗ script not found: %s%s\n' "$WF_C_RED" "$script" "$WF_C_RESET" >&2
    exit 1
  fi

  if bash "$script" "${args[@]}"; then
    printf '%s  ✓ %s%s\n' "$WF_C_GREEN" "$sname" "$WF_C_RESET"
  else
    rc=$?
    printf '%s  ✗ %s (exit %d)%s\n' "$WF_C_RED" "$sname" "$rc" "$WF_C_RESET" >&2
    exit "$rc"
  fi
done

printf '\n%s── done ──%s\n' "$WF_C_BOLD" "$WF_C_RESET"
