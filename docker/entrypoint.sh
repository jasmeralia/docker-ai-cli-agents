#!/usr/bin/env bash

set -euo pipefail

# --- Root phase: create host-matching user, then drop privileges via gosu ---
if [[ "${AI_CLI_PHASE:-}" != "user" ]]; then
  _ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }

  for _var in HOST_USER HOST_UID HOST_GID HOST_HOME HOST_CWD; do
    if [[ -z "${!_var:-}" ]]; then
      printf '[%s] [ERROR] %s is not set; use the wrapper script or pass all HOST_* env vars\n' \
        "$(_ts)" "${_var}" >&2
      exit 1
    fi
  done

  if [[ "${HOST_UID}" == "0" ]]; then
    printf '[%s] [ERROR] HOST_UID=0 — refusing to create a root identity. Use a non-root host user.\n' \
      "$(_ts)" >&2
    exit 1
  fi

  # Ensure the parent directory of HOST_HOME exists inside the container
  mkdir -p "$(dirname "${HOST_HOME}")"

  # Remove any existing user that already owns HOST_UID (e.g. "node" in node:* images)
  _uid_owner="$(getent passwd "${HOST_UID}" | cut -d: -f1 || true)"
  if [[ -n "${_uid_owner}" ]] && [[ "${_uid_owner}" != "${HOST_USER}" ]]; then
    userdel --force "${_uid_owner}"
  fi

  # Create a matching group for HOST_GID if none exists; reuse existing GID otherwise
  if ! getent group "${HOST_GID}" >/dev/null 2>&1; then
    groupadd -g "${HOST_GID}" "${HOST_USER}"
  fi

  # Create or align the user so UID, GID, home, and shell match the host
  if ! id "${HOST_USER}" >/dev/null 2>&1; then
    useradd --no-create-home \
      --uid "${HOST_UID}" --gid "${HOST_GID}" \
      --home-dir "${HOST_HOME}" --shell /bin/bash \
      "${HOST_USER}"
  else
    usermod --uid "${HOST_UID}" --gid "${HOST_GID}" \
      --home "${HOST_HOME}" --shell /bin/bash "${HOST_USER}"
  fi

  # Grant passwordless sudo
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${HOST_USER}" > "/etc/sudoers.d/${HOST_USER}"
  chmod 0440 "/etc/sudoers.d/${HOST_USER}"

  # Add to the docker socket's group so the user can reach the Docker daemon
  if [[ -S "/var/run/docker.sock" ]]; then
    _sock_gid="$(stat -c '%g' /var/run/docker.sock)"
    if ! getent group "${_sock_gid}" >/dev/null 2>&1; then
      groupadd -g "${_sock_gid}" dockerhost
    fi
    usermod -aG "${_sock_gid}" "${HOST_USER}"
  fi

  # Validate that HOST_CWD is reachable; fall back to HOST_HOME with a warning
  _target_cwd="${HOST_CWD}"
  if [[ ! -d "${HOST_CWD}" ]]; then
    printf '[%s] [WARN] HOST_CWD %s not found in container; falling back to %s\n' \
      "$(_ts)" "${HOST_CWD}" "${HOST_HOME}" >&2
    _target_cwd="${HOST_HOME}"
  fi

  exec gosu "${HOST_USER}" env \
    HOME="${HOST_HOME}" \
    HOST_CWD="${_target_cwd}" \
    AI_CLI_PHASE=user \
    "$0" "$@"
fi

# --- User phase: running as the host user ---

cd "${HOST_CWD}"

log_level="${AI_CLI_LOG_LEVEL:-info}"
serena_bin="${SERENA_BIN:-/usr/local/bin/serena}"
serena_project_cwd="${SERENA_PROJECT_CWD:-${HOST_CWD}}"
uvx_bin="${UVX_BIN:-/usr/local/bin/uvx}"
codex_plugin_dir="${CODEX_PLUGIN_DIR:-/opt/claude-plugins/codex}"

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

register_serena_codex() {
  local codex_config="${HOME}/.codex/config.toml"
  ensure_dir "${HOME}/.codex"
  if [[ -f "${codex_config}" ]] && grep -q '^\[mcp_servers\.serena\]' "${codex_config}"; then
    log DEBUG "Serena already registered with Codex"
    return 0
  fi
  log INFO "registering Serena MCP server with Codex"
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
log INFO "gh version: $(command_version gh)"

ensure_dir "${HOME}/.claude"
ensure_dir "${HOME}/.codex"

register_serena_claude
register_serena_codex

case "${run_mode}" in
  --claude)
    exec claude --plugin-dir "${codex_plugin_dir}" "$@"
    ;;
  --claude-safe)
    exec claude --plugin-dir "${codex_plugin_dir}" --permission-mode acceptEdits "$@"
    ;;
  --claude-yolo)
    exec claude --plugin-dir "${codex_plugin_dir}" --dangerously-skip-permissions "$@"
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
  --register-mcp-json)
    ensure_dir "${HOME}/.codex"
    exec python3 /usr/local/bin/register-mcp-json \
      "${1:-${serena_project_cwd}/.mcp.json}" \
      "${2:-${HOME}/.codex/config.toml}"
    ;;
  --shell)
    exec "${SHELL:-/bin/bash}" "$@"
    ;;
  *)
    log INFO "unknown selector '${run_mode}', expected --claude, --claude-safe, --claude-yolo, --codex, --codex-safe, --codex-yolo, --ccusage, --codexusage, --register-mcp-json, or --shell"
    exit 64
    ;;
esac
