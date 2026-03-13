#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <--codex|--claude|--shell> [args...]" >&2
  exit 64
fi

mode="$1"
shift

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_dir="$(pwd -P)"
myzstripe_src="${TN_MYZSTRIPE_SRC:-/mnt/myzstripe}"
myzmirror_src="${TN_MYZMIRROR_SRC:-/mnt/myzmirror}"
truenas_etc_src="${TN_TRUENAS_ETC_SRC:-/etc}"
default_home="/mnt/myzmirror/myzdset/morgan"
ai_cli_home="${AI_CLI_HOME:-${default_home}}"

detect_image() {
  if [[ -n "${TN_AI_CLI_IMAGE:-}" ]]; then
    printf '%s\n' "${TN_AI_CLI_IMAGE}"
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

  echo "unable to determine image reference; set TN_AI_CLI_IMAGE" >&2
  exit 1
}

tty_flags=(-i)
if [[ -t 0 && -t 1 ]]; then
  tty_flags=(-it)
fi

for source_path in "${myzstripe_src}" "${myzmirror_src}" "${truenas_etc_src}" "${workspace_dir}"; do
  if [[ ! -e "${source_path}" ]]; then
    echo "missing mount source: ${source_path}" >&2
    exit 1
  fi
done

image_ref="$(detect_image)"

exec docker run --rm "${tty_flags[@]}" \
  --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=${myzstripe_src},dst=/mnt/myzstripe" \
  --mount "type=bind,src=${myzmirror_src},dst=/mnt/myzmirror" \
  --mount "type=bind,src=${truenas_etc_src},dst=/mnt/truenas-etc,readonly" \
  --mount "type=bind,src=${workspace_dir},dst=/workdir" \
  --workdir /workdir \
  -e "AI_CLI_HOME=${ai_cli_home}" \
  -e "AI_CLI_LOG_LEVEL=${AI_CLI_LOG_LEVEL:-info}" \
  -e "HOME=${ai_cli_home}" \
  "${image_ref}" \
  "${mode}" "$@"
