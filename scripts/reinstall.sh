#!/usr/bin/env bash
# Forwards `che reinstall` to the repo's own install.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT/install.sh" "$@"
