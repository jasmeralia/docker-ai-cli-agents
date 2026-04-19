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

ensure_dir() {
  local dir="$1"
  if [[ -d "${dir}" ]]; then
    log DEBUG "directory exists: ${dir}"
    return 0
  fi
  if mkdir -p "${dir}" 2>/dev/null; then
    log INFO "created directory: ${dir}"
  else
    log INFO "directory missing and not writable: ${dir}"
  fi
}

register_serena_claude() {
  if ! claude mcp list 2>/dev/null | grep -q "^serena"; then
    log INFO "registering Serena MCP server with Claude Code"
    claude mcp add --scope user serena -- \
      serena start-mcp-server --context claude-code --project-from-cwd \
      2>/dev/null || log INFO "claude mcp add unavailable; skipping"
  else
    log DEBUG "Serena already registered with Claude Code"
  fi
}

register_serena_codex() {
  local codex_config="${HOME}/.codex/config.toml"
  ensure_dir "${HOME}/.codex"
  if ! grep -q '^\[mcp_servers\.serena\]' "${codex_config}" 2>/dev/null; then
    log INFO "registering Serena MCP server with Codex"
    cat >> "${codex_config}" <<'TOML'

[mcp_servers.serena]
command = "serena"
args = ["start-mcp-server", "--context", "claude-code", "--project-from-cwd"]
startup_timeout_sec = 15
tool_timeout_sec = 120
enabled = true
TOML
  else
    log DEBUG "Serena already registered with Codex"
  fi
}

run_mode="--claude"
if [[ $# -gt 0 ]]; then
  run_mode="$1"
  shift
fi

log INFO "selected runtime mode: ${run_mode}"
log INFO "working directory: $(pwd)"
log INFO "HOME=${HOME}"
log INFO "AI_CLI_LOG_LEVEL=${log_level}"
log INFO "claude version: $(command_version claude)"
log INFO "codex version: $(command_version codex)"
log INFO "ccusage version: $(command_version ccusage)"
log INFO "codex usage version: $(command_version ccusage-codex)"
log INFO "serena version: $(command_version serena)"

ensure_dir "${HOME}/.claude"
ensure_dir "${HOME}/.codex"

register_serena_claude
register_serena_codex

case "${run_mode}" in
  --claude)
    exec claude --dangerously-skip-permissions "$@"
    ;;
  --codex)
    exec codex --dangerously-bypass-approvals-and-sandbox "$@"
    ;;
  --ccusage)
    exec ccusage "$@"
    ;;
  --codexusage)
    exec ccusage-codex "$@"
    ;;
  --shell)
    exec "${SHELL:-/bin/bash}" "$@"
    ;;
  *)
    log INFO "unknown selector '${run_mode}', expected --claude, --codex, --ccusage, --codexusage, or --shell"
    exit 64
    ;;
esac
