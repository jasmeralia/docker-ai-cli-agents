#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <--claude|--codex|--ccusage|--codexusage|--shell> [--tag <image-tag>] [args...]" >&2
  exit 64
fi

mode="$1"
shift

# Parse --tag <value> from remaining args; forward everything else to the container
tag_override="${TN_AI_CLI_TAG:-}"
container_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      tag_override="$2"
      shift 2
      ;;
    *)
      container_args+=("$1")
      shift
      ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host_user="$(id -un)"
host_uid="$(id -u)"
host_gid="$(id -g)"
host_home="${HOME}"
host_cwd="$(pwd -P)"

detect_image() {
  local base_image

  if [[ -n "${TN_AI_CLI_IMAGE:-}" ]]; then
    base_image="${TN_AI_CLI_IMAGE}"
  elif [[ -n "${AI_CLI_IMAGE:-}" ]]; then
    base_image="${AI_CLI_IMAGE}"
  elif docker image inspect docker-ai-cli-agents:latest >/dev/null 2>&1; then
    base_image="docker-ai-cli-agents:latest"
  else
    local remote_url owner
    remote_url="$(git -C "${repo_root}" config --get remote.origin.url || true)"
    owner="$(printf '%s\n' "${remote_url}" | sed -nE 's#.*github\.com[:/]([^/]+)/docker-ai-cli-agents(\.git)?#\1#p')"
    if [[ -n "${owner}" ]]; then
      base_image="ghcr.io/${owner}/docker-ai-cli-agents:latest"
    else
      echo "unable to determine image reference; set TN_AI_CLI_IMAGE or AI_CLI_IMAGE" >&2
      exit 1
    fi
  fi

  if [[ -n "${tag_override}" ]]; then
    printf '%s\n' "${base_image%:*}:${tag_override}"
  else
    printf '%s\n' "${base_image}"
  fi
}

tty_flags=(-i)
if [[ -t 0 && -t 1 ]]; then
  tty_flags=(-it)
fi

# Build mount list: $HOME at its host path, /mnt if present, Docker socket if enabled.
# When the cwd falls outside both, bind it at its exact host path as a fallback.
mount_args=(--mount "type=bind,src=${host_home},dst=${host_home}")

if [[ -d "/mnt" ]]; then
  mount_args+=(--mount "type=bind,src=/mnt,dst=/mnt")
fi

case "${host_cwd}" in
  "${host_home}" | "${host_home}/"* | "/mnt" | "/mnt/"*)
    : ;;  # already covered by the $HOME or /mnt mount
  *)
    mount_args+=(--mount "type=bind,src=${host_cwd},dst=${host_cwd}") ;;
esac

# Mount the Docker socket by default; set SANDBOX_DOCKER=0 to disable.
# The -yolo scripts set this explicitly so the agent cannot reach host Docker.
if [[ "${SANDBOX_DOCKER:-1}" != "0" ]] && [[ -S "/var/run/docker.sock" ]]; then
  mount_args+=(--mount "type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock")
fi

image_ref="$(detect_image)"

# Pull latest when no specific tag is requested; skip re-pull for pinned tags.
pull_flag="--pull=missing"
if [[ -z "${tag_override}" ]]; then
  pull_flag="--pull=always"
fi

exec docker run --rm "${pull_flag}" "${tty_flags[@]}" \
  "${mount_args[@]}" \
  -e "HOST_USER=${host_user}" \
  -e "HOST_UID=${host_uid}" \
  -e "HOST_GID=${host_gid}" \
  -e "HOST_HOME=${host_home}" \
  -e "HOST_CWD=${host_cwd}" \
  -e "HOME=${host_home}" \
  -e "AI_CLI_LOG_LEVEL=${AI_CLI_LOG_LEVEL:-info}" \
  "${image_ref}" \
  "${mode}" "${container_args[@]}"
