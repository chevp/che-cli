#!/usr/bin/env bash
# Shared helpers for `che workflow` commands.
#
# A workflow is a YAML file under `<repo>/.che/workflow/<name>.yml` with this
# normalized shape:
#
#   name: release-desktop
#   description: Build mac + windows installers, publish GitHub release
#   inputs:
#     - name: tag
#       required: true
#       description: Release tag (vX.Y.Z)
#   steps:
#     - name: macOS build
#       script: scripts/build-electron-mac-thin-local.sh
#       args: ["--release", "${tag}"]
#
# Rules:
#   - Each step references an existing executable script (script:); no inline
#     bash. Workflows declare order, args, and inputs — never logic.
#   - `${input}` substitution happens once, before exec, on each args entry.
#   - Scripts run with the workflow root (the folder containing .che/) as CWD.
#
# Parsing uses mikefarah/yq (the Go binary). `che doctor workflow` checks for it.

WF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -t 1 ]; then
  WF_C_GREEN=$'\033[32m'; WF_C_RED=$'\033[31m'; WF_C_DIM=$'\033[2m'
  WF_C_BOLD=$'\033[1m';   WF_C_RESET=$'\033[0m'
else
  WF_C_GREEN=""; WF_C_RED=""; WF_C_DIM=""; WF_C_BOLD=""; WF_C_RESET=""
fi

wf_die() { echo "che workflow: $*" >&2; exit 1; }

# Locate the .che/workflow directory by walking up from $PWD. Sets globals
# WF_ROOT (folder containing .che/) and WF_DIR (.che/workflow inside it).
wf_find_dir() {
  local dir="$PWD"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -d "$dir/.che/workflow" ]; then
      WF_ROOT="$dir"
      WF_DIR="$dir/.che/workflow"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# Resolve a workflow name to a .yml/.yaml file path. Echoes the absolute path.
wf_resolve_file() {
  local name="$1"
  [ -n "$name" ] || wf_die "missing workflow name"
  wf_find_dir || wf_die "no .che/workflow/ found above $PWD"
  for ext in yml yaml; do
    if [ -f "$WF_DIR/$name.$ext" ]; then
      printf '%s\n' "$WF_DIR/$name.$ext"
      return 0
    fi
  done
  wf_die "workflow not found: $name (looked in $WF_DIR)"
}

# Verify yq is installed and is the Go variant (mikefarah). The python-yq has
# a different expression language and would silently produce wrong results.
wf_require_yq() {
  command -v yq >/dev/null 2>&1 \
    || wf_die "yq is required (https://github.com/mikefarah/yq) — run 'che doctor workflow'"
  if ! yq --version 2>&1 | grep -qi 'mikefarah\|version v\?[34]'; then
    wf_die "yq must be the mikefarah/yq Go binary (run 'che doctor workflow')"
  fi
}

# Read a scalar via yq. Returns the empty string when the path is null/missing.
wf_yq() {
  local expr="$1" file="$2"
  local out
  out="$(yq -r "$expr" "$file" 2>/dev/null || true)"
  [ "$out" = "null" ] && out=""
  printf '%s' "$out"
}

# Validate the top-level shape. Exits with a clear message on the first error.
wf_validate() {
  local file="$1"

  local name; name="$(wf_yq '.name' "$file")"
  [ -n "$name" ] || wf_die "$file: missing 'name'"

  local steps_len; steps_len="$(wf_yq '.steps | length' "$file")"
  [ "${steps_len:-0}" -gt 0 ] || wf_die "$file: 'steps' must be a non-empty list"

  local i
  for ((i = 0; i < steps_len; i++)); do
    local script; script="$(wf_yq ".steps[$i].script" "$file")"
    [ -n "$script" ] \
      || wf_die "$file: steps[$i] is missing 'script' (no inline bash allowed)"
  done
}

# Print all input names declared by a workflow, one per line.
wf_input_names() {
  local file="$1"
  local n; n="$(wf_yq '.inputs | length' "$file")"
  [ "${n:-0}" -gt 0 ] || return 0
  local i
  for ((i = 0; i < n; i++)); do
    wf_yq ".inputs[$i].name" "$file"
    printf '\n'
  done
}

# Print "1" if the named input is required, "0" otherwise.
wf_input_required() {
  local file="$1" name="$2"
  local req
  req="$(wf_yq "(.inputs[] | select(.name == \"$name\") | .required) // false" "$file")"
  [ "$req" = "true" ] && printf '1' || printf '0'
}

# Inputs are stored as parallel arrays (WF_INPUT_KEYS / WF_INPUT_VALS) because
# che targets bash 3.2 (the macOS system bash), which has no associative arrays.
WF_INPUT_KEYS=()
WF_INPUT_VALS=()

wf_input_set() {
  WF_INPUT_KEYS+=("$1")
  WF_INPUT_VALS+=("$2")
}

# Echo the value of an input, or empty string if unset.
wf_input_get() {
  local key="$1" i
  for i in "${!WF_INPUT_KEYS[@]}"; do
    if [ "${WF_INPUT_KEYS[$i]}" = "$key" ]; then
      printf '%s' "${WF_INPUT_VALS[$i]}"
      return 0
    fi
  done
  return 1
}

wf_input_has() { wf_input_get "$1" >/dev/null 2>&1; }

# Substitute ${key} placeholders in a string from the input arrays.
wf_substitute() {
  local s="$1" i k v
  for i in "${!WF_INPUT_KEYS[@]}"; do
    k="${WF_INPUT_KEYS[$i]}"
    v="${WF_INPUT_VALS[$i]}"
    s="${s//\$\{$k\}/$v}"
  done
  printf '%s' "$s"
}
