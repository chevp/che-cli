#!/usr/bin/env bash
# JSON helpers for provider clients. Backed by python3 (or python) so che-cli
# does not require jq. On Windows, `py -3` is also accepted.

_CHE_JSON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_CHE_JSON_DIR/python.sh"

_che_json_python() {
  if che_python_run "$@"; then
    return 0
  fi
  echo "che: need python3 (or python) - install via brew/apt/winget" >&2
  return 127
}

# json_string_literal <s>
json_string_literal() {
  CHE_JSON_IN="$1" _che_json_python -c 'import json,os,sys
sys.stdout.write(json.dumps(os.environ["CHE_JSON_IN"]))'
}

# json_extract <path> < input
json_extract() {
  CHE_JSON_PATH="$1" _che_json_python -c 'import json,os,re,sys
raw=sys.stdin.read()
if not raw.strip():
    sys.exit(0)
try:
    data=json.loads(raw)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)
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
