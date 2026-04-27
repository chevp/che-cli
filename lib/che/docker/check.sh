#!/usr/bin/env bash
# Verifies Docker is installed and the daemon is running.
# Defines: docker_check (returns 0 on success, 1 otherwise)

CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CHECK_DIR/platform.sh"
. "$CHECK_DIR/docker/client.sh"

type ok   >/dev/null 2>&1 || ok()   { printf "  ✓ %s\n" "$1"; }
type fail >/dev/null 2>&1 || fail() { printf "  ✗ %s\n" "$1"; }
type info >/dev/null 2>&1 || info() { printf "    %s\n" "$1"; }

docker_install_hint() {
  case "$CHE_OS" in
    darwin)    info "install: brew install --cask docker" ;;
    windows)
      info "install: re-run the che-cli installer with the 'Docker Desktop' task checked"
      info "         (or: winget install Docker.DockerDesktop / https://www.docker.com/products/docker-desktop/)"
      ;;
    wsl|linux) info "install: https://docs.docker.com/engine/install/" ;;
    *)         info "install: https://www.docker.com/get-started/" ;;
  esac
  info "docs:    https://docs.docker.com/get-started/"
}

docker_start_hint() {
  case "$CHE_OS" in
    darwin)  info "start it: open -a Docker" ;;
    windows) info "start Docker Desktop from the Start menu" ;;
    wsl)     info "ensure Docker Desktop's WSL integration is enabled" ;;
    linux)   info "start it: sudo systemctl start docker" ;;
  esac
}

docker_check() {
  if ! docker_installed; then
    fail "docker not installed"
    docker_install_hint
    return 1
  fi
  ok "docker installed ($(docker_version))"

  if docker_running; then
    ok "docker daemon is running"
    return 0
  else
    fail "docker daemon not running"
    docker_start_hint
    return 1
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "docker:"
  docker_check
fi
