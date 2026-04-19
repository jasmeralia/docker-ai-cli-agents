#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <--claude|--codex|--ccusage|--codexusage|--shell> [args...]" >&2
  exit 64
fi

mode="$1"
shift

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_dir="$(pwd -P)"
host_claude_dir="${HOME}/.claude"
host_claude_config="${HOME}/.claude.json"
host_codex_dir="${HOME}/.codex"
host_gh_dir="${HOME}/.config/gh"

detect_image() {
  if [[ -n "${TN_AI_CLI_IMAGE:-}" ]]; then
    printf '%s\n' "${TN_AI_CLI_IMAGE}"
    return 0
  fi

  if [[ -n "${AI_CLI_IMAGE:-}" ]]; then
    printf '%s\n' "${AI_CLI_IMAGE}"
    return 0
  fi

  if docker image inspect docker-ai-cli-agents:latest >/dev/null 2>&1; then
    printf '%s\n' "docker-ai-cli-agents:latest"
    return 0
  fi

  local remote_url owner
  remote_url="$(git -C "${repo_root}" config --get remote.origin.url || true)"
  owner="$(printf '%s\n' "${remote_url}" | sed -nE 's#.*github\.com[:/]([^/]+)/docker-ai-cli-agents(\.git)?#\1#p')"
  if [[ -n "${owner}" ]]; then
    printf 'ghcr.io/%s/docker-ai-cli-agents:latest\n' "${owner}"
    return 0
  fi

  echo "unable to determine image reference; set TN_AI_CLI_IMAGE or AI_CLI_IMAGE" >&2
  exit 1
}

tty_flags=(-i)
if [[ -t 0 && -t 1 ]]; then
  tty_flags=(-it)
fi

mkdir -p "${host_claude_dir}" "${host_codex_dir}" "${host_gh_dir}"
touch "${host_claude_config}"

docker_args=()
if [[ "${SANDBOX_DOCKER:-0}" == "1" ]]; then
  docker_args+=(--mount "type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock")
fi

image_ref="$(detect_image)"

exec docker run --rm "${tty_flags[@]}" \
  --mount "type=bind,src=${workspace_dir},dst=/workdir" \
  --mount "type=bind,src=${host_claude_dir},dst=/root/.claude" \
  --mount "type=bind,src=${host_claude_config},dst=/root/.claude.json" \
  --mount "type=bind,src=${host_codex_dir},dst=/root/.codex" \
  --mount "type=bind,src=${host_gh_dir},dst=/root/.config/gh" \
  "${docker_args[@]}" \
  --workdir /workdir \
  -e "HOME=/root" \
  -e "AI_CLI_LOG_LEVEL=${AI_CLI_LOG_LEVEL:-info}" \
  "${image_ref}" \
  "${mode}" "$@"
