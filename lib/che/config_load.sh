#!/usr/bin/env bash
# che config loader — sourced from bin/che on every invocation.
#
# Reads ~/.che/config (or $CHE_CONFIG_FILE) and exports CHE_* env vars from it,
# but ONLY if the variable isn't already set in the shell environment. So the
# precedence is: explicit env > saved config > built-in default. Format is plain
# `key=value`; unknown keys are ignored so the file is forward-compatible.

CHE_CONFIG_FILE="${CHE_CONFIG_FILE:-$HOME/.che/config}"

if [ -f "$CHE_CONFIG_FILE" ]; then
  while IFS='=' read -r _che_key _che_val; do
    case "$_che_key" in ''|\#*) continue ;; esac
    _che_key="${_che_key#"${_che_key%%[![:space:]]*}"}"
    _che_key="${_che_key%"${_che_key##*[![:space:]]}"}"
    [ -z "$_che_key" ] && continue
    _che_val="${_che_val#"${_che_val%%[![:space:]]*}"}"

    case "$_che_key" in
      provider)          _che_var=CHE_PROVIDER ;;
      ollama_host)       _che_var=CHE_OLLAMA_HOST ;;
      ollama_model)      _che_var=CHE_OLLAMA_MODEL ;;
      max_diff_chars)    _che_var=CHE_MAX_DIFF_CHARS ;;
      force_claude_code) _che_var=CHE_FORCE_CLAUDE_CODE ;;
      *) continue ;;
    esac

    if [ -z "${!_che_var:-}" ]; then
      export "$_che_var=$_che_val"
    fi
  done < "$CHE_CONFIG_FILE"
  unset _che_key _che_val _che_var
fi
