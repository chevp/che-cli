#!/usr/bin/env python3
"""Tiny YAML query helper used by lib/che/workflow/*.sh.

Replaces the old `yq` (mikefarah Go binary) dependency with a minimal subset
of yq's expression syntax — just enough for `che workflow` / `che run`:

    python yaml.py <file> '.name'
    python yaml.py <file> '.steps[0].script'
    python yaml.py <file> '.steps | length'

Path scalars print the value (empty string for null/missing). `| length` prints
the array length (0 for null/missing/non-array). Booleans print "true"/"false"
to match yq's text output.
"""
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "che workflow: PyYAML not installed. "
        "Install with: pip install pyyaml  (or: python -m pip install pyyaml). "
        "Run 'che doctor workflow' for help.\n"
    )
    sys.exit(2)


PATH_TOKEN = re.compile(r"\.([A-Za-z_][\w]*)|\[(\d+)\]")


def walk(doc, expr):
    cur = doc
    for name, idx in PATH_TOKEN.findall(expr):
        if cur is None:
            return None
        try:
            cur = cur[name] if name else cur[int(idx)]
        except (KeyError, IndexError, TypeError):
            return None
    return cur


def render(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float, str)):
        return str(value)
    return ""


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: yaml.py <file> <expr>\n")
        sys.exit(2)

    file_path, expr = sys.argv[1], sys.argv[2].strip()

    with open(file_path, "r", encoding="utf-8") as f:
        doc = yaml.safe_load(f)

    want_length = False
    if expr.endswith("| length") or expr.endswith("|length"):
        want_length = True
        expr = expr.rsplit("|", 1)[0].strip()

    value = doc if expr in ("", ".") else walk(doc, expr)

    if want_length:
        sys.stdout.write(str(len(value)) if isinstance(value, list) else "0")
    else:
        sys.stdout.write(render(value))


if __name__ == "__main__":
    main()
