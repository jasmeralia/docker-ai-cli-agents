# docker-ai-cli-agents

Docker image and automation for running both Codex CLI and Claude CLI in a single TrueNAS-friendly utility container.

## What this repo includes

- An Ubuntu-based image with both CLIs plus common development tools
- Usage analyzers for Claude Code (`ccusage`) and Codex CLI (`ccusage-codex`)
- A mode-selecting entrypoint for `--codex`, `--ccusage`, `--codexusage`, `--claude`, or `--shell`
- Global `codex`, `ccusage`, `ccusage-codex`, and `claude` binaries that work when the container runs as a non-root UID/GID
- `versions.json` as the single source of truth for release and CLI versions
- Jenkins automation for scheduled version detection and repo tagging
- GitHub Actions for image build and publish on tag push
- Sample TrueNAS custom app configuration

## Runtime assumptions

The container is designed to mount persistent CLI state outside the image:

- `/mnt/myzstripe:/mnt/myzstripe`
- `/mnt/myzmirror:/mnt/myzmirror`
- `/etc:/mnt/truenas-etc:ro`

Set `AI_CLI_HOME` to the dataset path that should contain:

- `${AI_CLI_HOME}/.codex`
- `${AI_CLI_HOME}/.claude`

The container workdir is `/workdir`. It is intentionally kept separate from `AI_CLI_HOME` so a bind-mounted host directory can appear as a clean working tree inside the container.

If `AI_CLI_HOME` is not overridden, the image defaults it to `/var/lib/ai-cli-home`.

## Build

```bash
docker build \
  --build-arg CODEX_VERSION="$(jq -r '.codex.version' versions.json)" \
  --build-arg CCUSAGE_VERSION="$(jq -r '.ccusage.version' versions.json)" \
  --build-arg CODEX_USAGE_VERSION="$(jq -r '.codex_usage.version' versions.json)" \
  --build-arg CLAUDE_VERSION="$(jq -r '.claude.version' versions.json)" \
  --build-arg REPO_RELEASE_VERSION="$(jq -r '.release_version' versions.json)" \
  -t ghcr.io/<owner>/docker-ai-cli-agents:latest .
```

## Run

Codex mode is the default:

```bash
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -e AI_CLI_HOME=/mnt/myzmirror/myzdset/morgan \
  -e HOME=/mnt/myzmirror/myzdset/morgan \
  --mount type=bind,src=/mnt/myzstripe,dst=/mnt/myzstripe \
  --mount type=bind,src=/mnt/myzmirror,dst=/mnt/myzmirror \
  --mount type=bind,src=/etc,dst=/mnt/truenas-etc,readonly \
  --mount type=bind,src="$(pwd)",dst=/workdir \
  --workdir /workdir \
  ghcr.io/<owner>/docker-ai-cli-agents:latest
```

Explicit modes:

```bash
docker run --rm -it image --codex
docker run --rm -it image --ccusage
docker run --rm -it image --codexusage
docker run --rm -it image --claude
docker run --rm -it image --shell
```

Arguments after the mode selector are passed through to the selected CLI or shell.

The usage analyzers read their data from the same persistent home directory mounted via `AI_CLI_HOME` and `HOME`, so they can inspect the local Claude Code and Codex usage history already stored under that path.

## Wrapper Scripts

The repo includes [tncodex](/home/morgan/git/docker-ai-cli-agents/tncodex), [tnccusage](/home/morgan/git/docker-ai-cli-agents/tnccusage), [tncodexusage](/home/morgan/git/docker-ai-cli-agents/tncodexusage), and [tnclaude](/home/morgan/git/docker-ai-cli-agents/tnclaude). They:

- mount `/mnt/myzstripe`, `/mnt/myzmirror`, and `/etc`
- bind-mount the current host directory to `/workdir`
- run the container as the current host UID/GID
- default `AI_CLI_HOME` to `/mnt/myzmirror/myzdset/morgan`
- set `HOME` to the same persistent path as `AI_CLI_HOME`

Optional overrides:

- `TN_AI_CLI_IMAGE` to pin the image reference
- `TN_MYZSTRIPE_SRC`, `TN_MYZMIRROR_SRC`, and `TN_TRUENAS_ETC_SRC` to change host-side mount sources while keeping the same in-container paths

Image selection is automatic:

- `TN_AI_CLI_IMAGE` if set
- otherwise local `docker-ai-cli-agents:latest` if present
- otherwise `ghcr.io/<github-owner>/docker-ai-cli-agents:latest` when the git remote can be parsed

Examples:

```bash
./tncodex
./tnccusage --help
./tncodexusage --help
./tnclaude --help
TN_AI_CLI_IMAGE=docker-ai-cli-agents:test-pinned ./tncodex --version
```

If you want to call `tncodex`, `tnccusage`, `tncodexusage`, or `tnclaude` without `./`, place the repo root on your `PATH` or symlink the scripts into a directory already on your `PATH`.

## Scripts

- `scripts/check_versions.sh`: compare `versions.json` against upstream versions
- `scripts/probe_claude_version.sh`: detect Claude version from the official installer inside a temp container
- `scripts/update_versions.py`: update `versions.json` and optionally bump the repo release version
- `scripts/smoke_test.sh`: run lightweight local checks and optional container smoke tests
