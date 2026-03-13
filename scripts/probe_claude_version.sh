#!/usr/bin/env bash

set -euo pipefail

image="${CLAUDE_PROBE_IMAGE:-ubuntu:24.04}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

version_output="$(
  docker run --rm "${image}" bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >/dev/null
    apt-get install -y --no-install-recommends bash ca-certificates curl >/dev/null
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null
    /root/.local/bin/claude --version
  '
)"

version="$(printf '%s\n' "${version_output}" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"

if [[ -z "${version}" ]]; then
  echo "failed to parse Claude version from: ${version_output}" >&2
  exit 1
fi

printf '%s\n' "${version}"
