#!/usr/bin/env bash
# JSON helpers for provider clients. Backed by python3 (or python) so che-cli
# does not require jq. Python 3 ships with macOS and virtually every Linux
# distro, and on Windows it's `winget install Python.Python.3` (~30 seconds).

_che_json_python() {
  if command -v python3 >/dev/null 2>&1; then
    python3 "$@"
  elif command -v python >/dev/null 2>&1; then
    python "$@"
  else
    echo "che: need python3 (or python) — install via brew/apt/winget" >&2
    return 127
  fi
}

# json_string_literal <s>
# Print a JSON-escaped, double-quoted string literal of $1, suitable for
# inlining into a JSON object: {"prompt": $(json_string_literal "$p"), ...}
json_string_literal() {
  CHE_JSON_IN="$1" _che_json_python -c 'import json,os,sys
sys.stdout.write(json.dumps(os.environ["CHE_JSON_IN"]))'
}

# json_extract <path> < input
# path syntax: dotted with optional [idx], e.g. ".response",
# ".choices[0].message.content". Prints the value as a string (empty if
# missing or null), matching jq -r "<path> // empty". Always exits 0.
json_extract() {
  CHE_JSON_PATH="$1" _che_json_python -c 'import json,os,re,sys
data=json.load(sys.stdin)
cur=data
for name,idx in re.findall(r"\.([A-Za-z_][\w]*)|\[(\d+)\]", os.environ["CHE_JSON_PATH"]):
    try:
        cur = cur[name] if name else cur[int(idx)]
    except (KeyError, IndexError, TypeError):
        cur=""
        break
if cur is None: cur=""
sys.stdout.write(cur if isinstance(cur, str) else json.dumps(cur))
sys.stdout.write("\n")'
}
