#!/usr/bin/env bash
# GitHub Copilot CLI wrapper. Like claude-code, this provider shells out to a
# CLI binary instead of speaking HTTP — auth (Copilot subscription) is owned
# by `copilot` itself, so che-cli never sees credentials.
# Requires: copilot on PATH (https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli).

copilot_ping() {
  command -v copilot >/dev/null 2>&1
}

# Copilot manages its own model selection — there is nothing to verify.
copilot_has_model() {
  return 0
}

# copilot_generate <prompt> [model_unused]
#
# Flags:
#   --prompt=VALUE     pass the prompt as an argument. Earlier versions of this
#                      wrapper piped the prompt to stdin with a bare `-p`, but
#                      `-p` requires a value (`-p PROMPT` / `--prompt=PROMPT`);
#                      without one, the CLI started in interactive mode and
#                      treated the stdin diff as raw user chat — producing
#                      "Ready — what should I do in this repo?" and tool-call
#                      progress lines as the "response", which then got
#                      committed verbatim as the commit message.
#                      Diffs are capped at CHE_MAX_DIFF_CHARS (default 8000),
#                      well under ARG_MAX on every supported shell.
#   -s / --silent      print only the agent response — required for scripting,
#                      strips usage stats and progress markers.
#   --no-color         no ANSI escapes leaking into the commit message.
#   --log-level=error  suppress info/debug chatter on stdout.
#   --allow-all-tools  required for non-interactive use (else the CLI hangs on
#                      permission prompts).
#   --deny-tool=shell  defensive: this is pure text generation; the agent has
#   --deny-tool=write  no business running shell commands or writing files
#                      while drafting a commit message. Deny takes precedence
#                      over --allow-all-tools.
copilot_generate() {
  local prompt="$1"
  command -v copilot >/dev/null 2>&1 || { echo "copilot CLI not on PATH" >&2; return 1; }
  copilot --prompt "$prompt" \
    --silent \
    --no-color \
    --log-level=error \
    --deny-tool=shell \
    --deny-tool=write \
    --allow-all-tools 2>/dev/null
}
