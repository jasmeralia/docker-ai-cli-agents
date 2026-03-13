#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
versions_file="${repo_root}/versions.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required" >&2
  exit 1
fi

codex_package="$(jq -r '.codex.package' "${versions_file}")"
current_codex="$(jq -r '.codex.version' "${versions_file}")"
current_claude="$(jq -r '.claude.version' "${versions_file}")"

latest_codex="$(npm view "${codex_package}" version)"
latest_claude="$("${repo_root}/scripts/probe_claude_version.sh")"

jq -n \
  --arg current_codex "${current_codex}" \
  --arg latest_codex "${latest_codex}" \
  --arg current_claude "${current_claude}" \
  --arg latest_claude "${latest_claude}" \
  '{
    codex: {
      current: $current_codex,
      latest: $latest_codex,
      changed: ($current_codex != $latest_codex)
    },
    claude: {
      current: $current_claude,
      latest: $latest_claude,
      changed: ($current_claude != $latest_claude)
    }
  }'
