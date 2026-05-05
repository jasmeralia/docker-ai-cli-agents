# docker-ai-cli-agents

Docker image and automation for running Claude Code and Codex CLI in a sandboxed utility container, with Serena MCP and optional Odoo MCP pre-configured for both agents.

## What this repo includes

- A Docker image built on top of the official `ghcr.io/anthropics/claude-code` sandbox image
- Both Claude Code (`claude`) and Codex CLI (`codex`) plus common development tools
- Usage analyzers: `ccusage` (Claude Code) and `ccusage-codex` (Codex CLI)
- [Serena MCP](https://github.com/oraios/serena) — code intelligence server, always registered for both agents on startup
- [Odoo MCP](https://github.com/ivnvxd/mcp-server-odoo) — Odoo ERP integration, registered automatically when `ODOO_URL` is set
- A mode-selecting entrypoint for `--claude`, `--codex`, `--ccusage`, `--codexusage`, or `--shell`
- `versions.json` as the single source of truth for release and CLI versions
- Jenkins automation for scheduled version detection and repo tagging
- GitHub Actions for image build and publish on tag push
- Sample TrueNAS custom app configuration

## Build

```bash
make build
```

Or manually with explicit versions:

```bash
docker build \
  --build-arg CODEX_VERSION="$(jq -r '.codex.version' versions.json)" \
  --build-arg CCUSAGE_VERSION="$(jq -r '.ccusage.version' versions.json)" \
  --build-arg CODEX_USAGE_VERSION="$(jq -r '.codex_usage.version' versions.json)" \
  --build-arg REPO_RELEASE_VERSION="$(jq -r '.release_version' versions.json)" \
  -t docker-ai-cli-agents:latest .
```

Claude Code itself comes from the base image — no separate version pin is needed.

## Run

Default mode is `--claude`:

```bash
docker run --rm -it \
  --mount type=bind,src="$(pwd)",dst=/workdir \
  --mount type=bind,src="${HOME}/.claude",dst=/root/.claude \
  --mount type=bind,src="${HOME}/.claude.json",dst=/root/.claude.json \
  --mount type=bind,src="${HOME}/.codex",dst=/root/.codex \
  --workdir /workdir \
  -e HOME=/root \
  ghcr.io/<owner>/docker-ai-cli-agents:latest
```

Explicit modes:

```bash
docker run --rm -it image --claude
docker run --rm -it image --codex
docker run --rm -it image --ccusage
docker run --rm -it image --codexusage
docker run --rm -it image --shell
```

Arguments after the mode selector are passed through to the selected CLI or shell.

## Wrapper scripts

The `bin/` directory contains `tnclaude`, `tncodex`, `tnccusage`, and `tncodexusage`. These are thin wrappers around `scripts/run_with_truenas_mounts.sh` that:

- Bind-mount the current host directory to `/workdir`
- Bind-mount `~/.claude`, `~/.claude.json`, `~/.codex`, and `~/.config/gh` from the host so config and auth persist between container runs
- Auto-detect the image reference (see below)
- Forward all arguments to the selected mode

```bash
bin/tnclaude
bin/tncodex
bin/tnccusage --help
bin/tncodexusage --help
```

To call without `bin/`, add the repo root or `bin/` to your `PATH`, or symlink the scripts into a directory already on your `PATH`.

**Image detection order** (first match wins):

1. `TN_AI_CLI_IMAGE` env var
2. `AI_CLI_IMAGE` env var
3. Local `docker-ai-cli-agents:latest` if present
4. `ghcr.io/<github-owner>/docker-ai-cli-agents:latest` parsed from the git remote

**Optional flags:**

- `SANDBOX_DOCKER=1` — also mounts `/var/run/docker.sock` into the container
- `AI_CLI_LOG_LEVEL=debug` — enables verbose startup logging

## MCP servers

Both agents have MCP servers registered automatically by the entrypoint on every container start.

### Serena (always active)

[Serena](https://github.com/oraios/serena) provides code-intelligence tools (symbol search, semantic editing, diagnostics). It is registered unconditionally for both Claude Code and Codex on every start. No configuration is required.

The entrypoint always refreshes the Codex registration so that stale config from previous container versions is repaired automatically.

### Odoo (conditional on `ODOO_URL`)

[Odoo MCP](https://github.com/ivnvxd/mcp-server-odoo) connects to an Odoo ERP instance and exposes tools for searching, reading, creating, and updating records. It is registered only when `ODOO_URL` is set in the container environment.

**Required variables** (`ODOO_URL` plus one authentication option):

| Variable | Description |
|---|---|
| `ODOO_URL` | Odoo instance URL, e.g. `https://mycompany.odoo.com` |
| `ODOO_API_KEY` | API key (preferred) |
| `ODOO_USER` | Username (alternative to API key) |
| `ODOO_PASSWORD` | Password (required with `ODOO_USER`) |

**Optional variables:**

| Variable | Description |
|---|---|
| `ODOO_DB` | Database name (auto-detected if omitted; required when listing is restricted) |
| `ODOO_LOCALE` | Response locale, e.g. `fr_FR` |
| `ODOO_YOLO` | `read` or `true` — bypasses MCP module requirement (dev/testing only) |

**Passing credentials with the wrapper scripts:**

Export the variables before running the wrapper, or set them inline:

```bash
export ODOO_URL=https://mycompany.odoo.com
export ODOO_API_KEY=your-api-key-here
export ODOO_DB=mycompany
bin/tnclaude
```

```bash
ODOO_URL=https://mycompany.odoo.com ODOO_API_KEY=your-key bin/tncodex
```

**Passing credentials with `docker run` directly:**

```bash
docker run --rm -it \
  --mount type=bind,src="$(pwd)",dst=/workdir \
  --mount type=bind,src="${HOME}/.claude",dst=/root/.claude \
  --mount type=bind,src="${HOME}/.claude.json",dst=/root/.claude.json \
  --mount type=bind,src="${HOME}/.codex",dst=/root/.codex \
  --workdir /workdir \
  -e HOME=/root \
  -e ODOO_URL=https://mycompany.odoo.com \
  -e ODOO_API_KEY=your-api-key-here \
  -e ODOO_DB=mycompany \
  ghcr.io/<owner>/docker-ai-cli-agents:latest --claude
```

The credentials are written into `~/.claude` (Claude Code MCP config) and `~/.codex/config.toml` (Codex MCP config) inside the container. Because these directories are bind-mounted from the host, the registration persists across runs. On each new start the Odoo registration is always refreshed, so changing credentials takes effect immediately on the next container invocation.

> **Security note:** Odoo credentials are stored in `~/.claude` and `~/.codex` on the host filesystem. Restrict permissions on those directories accordingly and avoid committing them to version control.

## Scripts

- `scripts/run_with_truenas_mounts.sh` — run any mode with standard host mounts (used by `bin/tn*`)
- `scripts/check_versions.sh` — compare `versions.json` against upstream versions
- `scripts/update_versions.py` — update `versions.json` and optionally bump the repo release version
- `scripts/smoke_test.sh` — lightweight local checks and optional container smoke tests

## Make targets

| Target | Description |
|---|---|
| `make lint` | Run hadolint, shellcheck, yamllint, ruff, and smoke tests |
| `make lint SMOKE_IMAGE=docker-ai-cli-agents:test` | Also run container smoke tests |
| `make build` | Build the image with pinned versions from `versions.json` |
| `make build IMAGE=docker-ai-cli-agents:test` | Build with a custom tag |
| `make check-versions` | Print upstream version report |
| `make update-versions UPDATE_ARGS='--codex-version 1.2.3 --bump-release patch'` | Update `versions.json` |
