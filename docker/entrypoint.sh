#!/usr/bin/env bash

set -euo pipefail

log_level="${AI_CLI_LOG_LEVEL:-info}"
serena_bin="${SERENA_BIN:-/root/.local/bin/serena}"
serena_project_cwd="${SERENA_PROJECT_CWD:-/workdir}"
uvx_bin="${UVX_BIN:-/root/.local/bin/uvx}"

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
      "${serena_bin}" start-mcp-server --context=claude-code --project-from-cwd \
      2>/dev/null || log INFO "claude mcp add unavailable; skipping"
  else
    log DEBUG "Serena already registered with Claude Code"
  fi
}

remove_codex_serena_config() {
  local codex_config="$1"
  local tmp_config
  [[ -f "${codex_config}" ]] || return 0

  tmp_config="$(mktemp "${codex_config}.XXXXXX")"
  awk '
    /^\[/ {
      header = $0
      gsub(/[[:space:]]/, "", header)
      gsub(/["'\'']/, "", header)
      if (header == "[mcp_servers.serena]") {
        skip = 1
        next
      }
      skip = 0
    }
    !skip { print }
  ' "${codex_config}" > "${tmp_config}"
  mv "${tmp_config}" "${codex_config}"
}

register_serena_codex() {
  local codex_config="${HOME}/.codex/config.toml"
  ensure_dir "${HOME}/.codex"
  if [[ -f "${codex_config}" ]] && awk '
    /^\[/ {
      header = $0
      gsub(/[[:space:]]/, "", header)
      gsub(/["'\'']/, "", header)
      if (header == "[mcp_servers.serena]") {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' "${codex_config}"; then
    log INFO "refreshing Serena MCP server registration with Codex"
    remove_codex_serena_config "${codex_config}"
  else
    log INFO "registering Serena MCP server with Codex"
  fi
  cat >> "${codex_config}" <<TOML

[mcp_servers.serena]
command = "${serena_bin}"
args = ["start-mcp-server", "--project-from-cwd", "--context=codex"]
cwd = "${serena_project_cwd}"
startup_timeout_sec = 60
tool_timeout_sec = 120
enabled = true
TOML
}

register_odoo_claude() {
  if [[ -z "${ODOO_URL:-}" ]]; then
    log DEBUG "ODOO_URL not set; skipping Odoo MCP registration for Claude Code"
    return 0
  fi
  log INFO "registering Odoo MCP server with Claude Code (url: ${ODOO_URL})"
  claude mcp remove --scope user odoo 2>/dev/null || true
  local env_args=("--env" "ODOO_URL=${ODOO_URL}")
  [[ -n "${ODOO_API_KEY:-}" ]]  && env_args+=(--env "ODOO_API_KEY=${ODOO_API_KEY}")
  [[ -n "${ODOO_USER:-}" ]]     && env_args+=(--env "ODOO_USER=${ODOO_USER}")
  [[ -n "${ODOO_PASSWORD:-}" ]] && env_args+=(--env "ODOO_PASSWORD=${ODOO_PASSWORD}")
  [[ -n "${ODOO_DB:-}" ]]       && env_args+=(--env "ODOO_DB=${ODOO_DB}")
  [[ -n "${ODOO_LOCALE:-}" ]]   && env_args+=(--env "ODOO_LOCALE=${ODOO_LOCALE}")
  [[ -n "${ODOO_YOLO:-}" ]]     && env_args+=(--env "ODOO_YOLO=${ODOO_YOLO}")
  claude mcp add --scope user "${env_args[@]}" odoo -- \
    "${uvx_bin}" mcp-server-odoo \
    2>/dev/null || log INFO "claude mcp add unavailable; skipping"
}

remove_codex_odoo_config() {
  local codex_config="$1"
  local tmp_config
  [[ -f "${codex_config}" ]] || return 0

  tmp_config="$(mktemp "${codex_config}.XXXXXX")"
  awk '
    /^\[/ {
      header = $0
      gsub(/[[:space:]]/, "", header)
      gsub(/["'"'"']/, "", header)
      if (header ~ /^\[mcp_servers\.odoo]/ || header ~ /^\[mcp_servers\.odoo\./) {
        skip = 1
        next
      }
      skip = 0
    }
    !skip { print }
  ' "${codex_config}" > "${tmp_config}"
  mv "${tmp_config}" "${codex_config}"
}

register_odoo_codex() {
  if [[ -z "${ODOO_URL:-}" ]]; then
    log DEBUG "ODOO_URL not set; skipping Odoo MCP registration for Codex"
    return 0
  fi
  local codex_config="${HOME}/.codex/config.toml"
  ensure_dir "${HOME}/.codex"
  log INFO "registering Odoo MCP server with Codex (url: ${ODOO_URL})"
  remove_codex_odoo_config "${codex_config}"
  cat >> "${codex_config}" <<TOML

[mcp_servers.odoo]
command = "${uvx_bin}"
args = ["mcp-server-odoo"]
startup_timeout_sec = 30
tool_timeout_sec = 120
enabled = true

[mcp_servers.odoo.env]
ODOO_URL = "${ODOO_URL}"
TOML
  [[ -n "${ODOO_API_KEY:-}" ]]  && printf 'ODOO_API_KEY = "%s"\n'  "${ODOO_API_KEY}"  >> "${codex_config}"
  [[ -n "${ODOO_USER:-}" ]]     && printf 'ODOO_USER = "%s"\n'     "${ODOO_USER}"     >> "${codex_config}"
  [[ -n "${ODOO_PASSWORD:-}" ]] && printf 'ODOO_PASSWORD = "%s"\n' "${ODOO_PASSWORD}" >> "${codex_config}"
  [[ -n "${ODOO_DB:-}" ]]       && printf 'ODOO_DB = "%s"\n'       "${ODOO_DB}"       >> "${codex_config}"
  [[ -n "${ODOO_LOCALE:-}" ]]   && printf 'ODOO_LOCALE = "%s"\n'   "${ODOO_LOCALE}"   >> "${codex_config}"
  [[ -n "${ODOO_YOLO:-}" ]]     && printf 'ODOO_YOLO = "%s"\n'     "${ODOO_YOLO}"     >> "${codex_config}"
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
log INFO "serena version: $(command_version "${serena_bin}")"
log INFO "uvx version: $(command_version "${uvx_bin}")"

ensure_dir "${HOME}/.claude"
ensure_dir "${HOME}/.codex"

register_serena_claude
register_serena_codex
register_odoo_claude
register_odoo_codex

case "${run_mode}" in
  --claude)
    exec claude "$@"
    ;;
  --claude-safe)
    exec claude --permission-mode acceptEdits "$@"
    ;;
  --claude-yolo)
    exec claude --dangerously-skip-permissions "$@"
    ;;
  --codex)
    exec codex "$@"
    ;;
  --codex-safe)
    exec codex -a untrusted "$@"
    ;;
  --codex-yolo)
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
    log INFO "unknown selector '${run_mode}', expected --claude, --claude-safe, --claude-yolo, --codex, --codex-safe, --codex-yolo, --ccusage, --codexusage, or --shell"
    exit 64
    ;;
esac
