#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image_ref="${1:-}"

bash -n "${repo_root}/docker/entrypoint.sh"

if [[ -n "${image_ref}" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required for image smoke tests" >&2
    exit 1
  fi

  # The entrypoint requires HOST_* identity env vars and a reachable HOME/CWD.
  # Use a temp directory as a minimal stand-in for both.
  smoke_home="$(mktemp -d)"
  trap 'rm -rf "${smoke_home}"' EXIT

  smoke_run() {
    docker run --rm \
      --mount "type=bind,src=${smoke_home},dst=${smoke_home}" \
      -e "HOST_USER=$(id -un)" \
      -e "HOST_UID=$(id -u)" \
      -e "HOST_GID=$(id -g)" \
      -e "HOST_HOME=${smoke_home}" \
      -e "HOST_CWD=${smoke_home}" \
      -e "HOME=${smoke_home}" \
      "${image_ref}" "$@"
  }

  smoke_run --codex --version >/dev/null
  smoke_run --ccusage --version >/dev/null
  smoke_run --codexusage --version >/dev/null
  smoke_run --claude --version >/dev/null
fi

echo "smoke tests passed"
