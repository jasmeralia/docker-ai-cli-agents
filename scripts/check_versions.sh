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
ccusage_package="$(jq -r '.ccusage.package' "${versions_file}")"
codex_usage_package="$(jq -r '.codex_usage.package' "${versions_file}")"
current_codex="$(jq -r '.codex.version' "${versions_file}")"
current_ccusage="$(jq -r '.ccusage.version' "${versions_file}")"
current_codex_usage="$(jq -r '.codex_usage.version' "${versions_file}")"

latest_codex="$(npm view "${codex_package}" version)"
latest_ccusage="$(npm view "${ccusage_package}" version)"
latest_codex_usage="$(npm view "${codex_usage_package}" version)"

jq -n \
  --arg current_codex "${current_codex}" \
  --arg latest_codex "${latest_codex}" \
  --arg current_ccusage "${current_ccusage}" \
  --arg latest_ccusage "${latest_ccusage}" \
  --arg current_codex_usage "${current_codex_usage}" \
  --arg latest_codex_usage "${latest_codex_usage}" \
  '{
    codex: {
      current: $current_codex,
      latest: $latest_codex,
      changed: ($current_codex != $latest_codex)
    },
    ccusage: {
      current: $current_ccusage,
      latest: $latest_ccusage,
      changed: ($current_ccusage != $latest_ccusage)
    },
    codex_usage: {
      current: $current_codex_usage,
      latest: $latest_codex_usage,
      changed: ($current_codex_usage != $latest_codex_usage)
    }
  }'
