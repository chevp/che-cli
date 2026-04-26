#!/usr/bin/env bash
# Thin wrapper around the docker CLI for installation/health checks.

docker_installed() { command -v docker >/dev/null 2>&1; }

docker_running() {
  docker_installed && docker info >/dev/null 2>&1
}

docker_version() {
  docker_installed || return 1
  docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
}
