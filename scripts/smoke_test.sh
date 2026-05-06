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
  docker run --rm "${image_ref}" --codex --version >/dev/null
  docker run --rm "${image_ref}" --ccusage --version >/dev/null
  docker run --rm "${image_ref}" --codexusage --version >/dev/null
  docker run --rm "${image_ref}" --claude --version >/dev/null
fi

echo "smoke tests passed"
