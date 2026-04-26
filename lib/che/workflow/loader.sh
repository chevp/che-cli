#!/usr/bin/env bash
# Shared helpers for `che workflow` commands.
#
# A workflow is a YAML file under `<repo>/.che/workflows/<name>.yml` with this
# normalized shape (see docs/workflow.md):
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
# Parsing uses Python + PyYAML (see workflow/yaml_get.py). `che doctor workflow`
# checks for both. We don't depend on the `yq` binary anymore.

WF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF_YAML_GET="$WF_LIB_DIR/workflow/yaml_get.py"

if [ -t 1 ]; then
  WF_C_GREEN=$'\033[32m'; WF_C_RED=$'\033[31m'; WF_C_DIM=$'\033[2m'
  WF_C_BOLD=$'\033[1m';   WF_C_RESET=$'\033[0m'
else
  WF_C_GREEN=""; WF_C_RED=""; WF_C_DIM=""; WF_C_BOLD=""; WF_C_RESET=""
fi

wf_die() { echo "che workflow: $*" >&2; exit 1; }

# Locate the .che/workflows directory by walking up from $PWD.
# Sets globals (must NOT be called inside $(…) — that subshell loses them):
#   WF_ROOT — folder containing .che/
#   WF_DIR  — .che/workflows inside it
WF_ROOT=""
WF_DIR=""
WF_FILE=""

wf_find_dir() {
  local dir="$PWD"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -d "$dir/.che/workflows" ]; then
      WF_ROOT="$dir"
      WF_DIR="$dir/.che/workflows"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# Resolve a workflow name; sets WF_FILE (alongside WF_ROOT/WF_DIR from
# wf_find_dir). Call directly — do NOT wrap in $().
wf_resolve_file() {
  local name="$1"
  [ -n "$name" ] || wf_die "missing workflow name"
  wf_find_dir || wf_die "no .che/workflows/ found above $PWD"
  local ext
  for ext in yml yaml; do
    if [ -f "$WF_DIR/$name.$ext" ]; then
      WF_FILE="$WF_DIR/$name.$ext"
      return 0
    fi
  done
  wf_die "workflow not found: $name (looked in $WF_DIR)"
}

# Resolve a python interpreter that actually runs.
#
# On Windows, `python3` on PATH is often a Microsoft Store App Execution Alias
# stub that resolves via `command -v` but does not actually execute — it just
# prompts the user to install Python from the Store. So we probe each candidate
# by running it, not just by checking PATH.
_wf_python() {
  local cand
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 \
       && "$cand" -c '' >/dev/null 2>&1; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

# Verify Python + PyYAML are available. Both are needed to parse workflow files.
wf_require_yq() {
  local py
  py="$(_wf_python)" \
    || wf_die "python3 (or python) is required — run 'che doctor workflow'"
  if ! "$py" -c 'import yaml' >/dev/null 2>&1; then
    wf_die "PyYAML is required (pip install pyyaml) — run 'che doctor workflow'"
  fi
}

# Read a scalar from a workflow YAML. Returns the empty string for null/missing.
# Supported expressions:
#   .path.with.dots           scalar (string/int/bool)
#   .path[0].with[1]          scalar with array indexes
#   .path | length            length of an array (0 if missing/non-array)
wf_yq() {
  local expr="$1" file="$2"
  local py; py="$(_wf_python)" || return 1
  "$py" "$WF_YAML_GET" "$file" "$expr" 2>/dev/null || true
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

# Look up a workflow by its declared `trigger:` (string or list-of-strings).
# On a unique match, sets WF_ROOT / WF_DIR / WF_FILE and prints the workflow's
# filename stem. Returns:
#   0 — single match (output usable as `che run <stem>`)
#   1 — no match, no workflows dir, or yq unavailable (silent)
#   2 — multiple workflows declare the same trigger (diagnostic on stderr)
#
# Unlike most helpers here, this never calls wf_die — the dispatcher uses it
# as a soft probe before falling through to built-ins.
wf_resolve_trigger() {
  local trig="$1"
  [ -n "$trig" ] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  wf_find_dir || return 1

  local f kind n i t matches=()
  shopt -s nullglob
  for f in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
    kind="$(yq -r '.trigger | tag' "$f" 2>/dev/null || true)"
    case "$kind" in
      '!!str')
        t="$(yq -r '.trigger' "$f" 2>/dev/null || true)"
        [ "$t" = "$trig" ] && matches+=("$f")
        ;;
      '!!seq')
        n="$(yq -r '.trigger | length' "$f" 2>/dev/null || echo 0)"
        for ((i = 0; i < ${n:-0}; i++)); do
          t="$(yq -r ".trigger[$i]" "$f" 2>/dev/null || true)"
          if [ "$t" = "$trig" ]; then matches+=("$f"); break; fi
        done
        ;;
    esac
  done
  shopt -u nullglob

  case "${#matches[@]}" in
    0) return 1 ;;
    1)
      WF_FILE="${matches[0]}"
      local base; base="$(basename "$WF_FILE")"
      printf '%s' "${base%.*}"
      return 0
      ;;
    *)
      echo "che: trigger '$trig' is declared by multiple workflows:" >&2
      for f in "${matches[@]}"; do echo "  - $f" >&2; done
      return 2
      ;;
  esac
}

# Print "1" if the named input is required, "0" otherwise.
wf_input_required() {
  local file="$1" name="$2"
  local n; n="$(wf_yq '.inputs | length' "$file")"
  [ "${n:-0}" -gt 0 ] || { printf '0'; return; }
  local i in_name in_req
  for ((i = 0; i < n; i++)); do
    in_name="$(wf_yq ".inputs[$i].name" "$file")"
    if [ "$in_name" = "$name" ]; then
      in_req="$(wf_yq ".inputs[$i].required" "$file")"
      [ "$in_req" = "true" ] && printf '1' || printf '0'
      return
    fi
  done
  printf '0'
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
