#!/usr/bin/env bash
# Cross-cutting OS detection. Sourced by other modules.
# Sets: $CHE_OS = darwin | windows | wsl | linux | unknown

detect_platform() {
  case "$(uname -s)" in
    Darwin*)
      CHE_OS=darwin
      ;;
    Linux*)
      if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
        CHE_OS=wsl
      else
        CHE_OS=linux
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      CHE_OS=windows
      ;;
    *)
      CHE_OS=unknown
      ;;
  esac
  export CHE_OS
}

# Auto-detect on source.
detect_platform
