#!/usr/bin/env bash

set -euo pipefail

log_level="${AI_CLI_LOG_LEVEL:-info}"

timestamp() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

should_log_debug() {
  [[ "${log_level}" == "debug" ]]
}

log() {
  local level="$1"
  shift
  if [[ "${level}" == "DEBUG" ]] && ! should_log_debug; then
    return 0
  fi
  printf '[%s] [%s] %s\n' "$(timestamp)" "${level}" "$*"
}

command_version() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    "${cmd}" --version 2>&1 | head -n 1
  else
    printf '%s not installed\n' "${cmd}"
  fi
}

ensure_state_dir() {
  local dir="$1"
  if [[ -d "${dir}" ]]; then
    log DEBUG "state directory exists: ${dir}"
    return 0
  fi

  if mkdir -p "${dir}" 2>/dev/null; then
    log INFO "created state directory: ${dir}"
  else
    log INFO "state directory missing and not writable: ${dir}"
  fi
}

print_mount_status() {
  local path
  for path in /mnt/myzstripe /mnt/myzmirror /mnt/truenas-etc; do
    if [[ -e "${path}" ]]; then
      log INFO "mount available: ${path}"
    else
      log INFO "mount not present: ${path}"
    fi
  done
}

run_mode="--codex"
if [[ $# -gt 0 ]]; then
  run_mode="$1"
  shift
fi

ai_cli_home="${AI_CLI_HOME:-/var/lib/ai-cli-home}"
codex_home="${ai_cli_home}/.codex"
claude_home="${ai_cli_home}/.claude"

log INFO "selected runtime mode: ${run_mode}"
log INFO "working directory: $(pwd)"
log INFO "AI_CLI_HOME=${ai_cli_home}"
log INFO "AI_CLI_LOG_LEVEL=${log_level}"
log INFO "codex version: $(command_version codex)"
log INFO "ccusage version: $(command_version ccusage)"
log INFO "codex usage version: $(command_version ccusage-codex)"
log INFO "claude version: $(command_version claude)"

print_mount_status
ensure_state_dir "${codex_home}"
ensure_state_dir "${claude_home}"

case "${run_mode}" in
  --codex)
    exec codex "$@"
    ;;
  --ccusage)
    exec ccusage "$@"
    ;;
  --codexusage)
    exec ccusage-codex "$@"
    ;;
  --claude)
    exec claude "$@"
    ;;
  --shell)
    exec "${SHELL:-/bin/bash}" "$@"
    ;;
  *)
    log INFO "unknown selector '${run_mode}', expected --codex, --ccusage, --codexusage, --claude, or --shell"
    exit 64
    ;;
esac
