# docker-ai-cli-agents — Project Context

## Developer Entry Points

Prefer the repo `Makefile` for routine validation and image creation:

- `make lint` — runs hadolint, shellcheck, yamllint, ruff, and the smoke tests
- `make lint SMOKE_IMAGE=docker-ai-cli-agents:test` — also runs container smoke checks
- `make build` — builds the Docker image with pinned versions from `versions.json`
- `make build IMAGE=docker-ai-cli-agents:test` — build with a custom tag
- `make check-versions` — prints the upstream version report used by automation
- `make update-versions UPDATE_ARGS='--codex-version 1.2.3 --bump-release patch'` — forwards arguments to `scripts/update_versions.py`

When making changes, always refresh `versions.json` with `make check-versions` and `make update-versions` unless there is a specific reason not to.

When making code changes, always update `README.md` and `AGENTS.md` to reflect what changed — entrypoint behavior, new env vars, new MCP servers, changed script paths, new make targets, etc. Documentation is part of the changeset, not a follow-up task.

---

## Purpose

This repository provides a Docker image containing Claude Code (`claude`) and Codex CLI (`codex`) so they can run in sandboxed environments — originally designed for TrueNAS SCALE but usable anywhere Docker runs.

Primary goals:

- Provide one container image with both CLIs plus Serena MCP and Odoo MCP support
- Support subscription-based authentication (Claude account for Claude Code, ChatGPT subscription for Codex)
- Maintain persistent CLI configuration directories outside the container via bind mounts
- Provide automated version detection, build, and publishing pipelines
- Provide clean stdout logging compatible with tools like Dozzle

---

## Base Image

`node:20`

Matches Anthropic's own devcontainer base. Claude Code is installed via the official install script (`curl -fsSL https://claude.ai/install.sh | bash -s stable`) which always pulls the latest stable release. It is not version-pinned in `versions.json` — the `stable` channel is the source of truth.

---

## Container Runtime Layout

The entrypoint expects the following bind mounts for persistent state:

| Host path | Container path | Purpose |
|---|---|---|
| `~/.claude` | `/root/.claude` | Claude Code config, MCP registrations, auth |
| `~/.claude.json` | `/root/.claude.json` | Claude Code account config |
| `~/.codex` | `/root/.codex` | Codex config including MCP server config |
| `~/.config/gh` | `/root/.config/gh` | GitHub CLI auth |
| `<workspace>` | `/workdir` | User project files |

The `scripts/run_with_truenas_mounts.sh` script and `bin/tn*` wrappers set these up automatically.

---

## Entrypoint Behavior

The container entrypoint (`docker/entrypoint.sh`) selects a runtime mode via its first argument. Default is `--claude`.

| Flag | Runs |
|---|---|
| `--claude` | `claude --dangerously-skip-permissions` |
| `--codex` | `codex --dangerously-bypass-approvals-and-sandbox` |
| `--ccusage` | `ccusage` |
| `--codexusage` | `ccusage-codex` |
| `--shell` | `$SHELL` (bash) |

Arguments after the selector are passed to the chosen CLI.

On startup the entrypoint:
1. Logs versions of all installed tools
2. Ensures `~/.claude` and `~/.codex` exist
3. Registers Serena MCP with Claude Code (if not already registered)
4. Always refreshes the Serena MCP registration in Codex config
5. If `ODOO_URL` is set: registers Odoo MCP with Claude Code (always refreshes) and Codex (always refreshes)

---

## MCP Servers

### Serena

Installed via `uv tool install -p 3.13 serena-agent@latest`. Binary at `/root/.local/bin/serena` (env var `SERENA_BIN`).

Registered for Claude Code with `--context=claude-code` and for Codex with `--context=codex`. Both use `--project-from-cwd` so Serena detects the project from `/workdir`. Codex registration also sets `cwd = "/workdir"` to ensure the working directory is correct when Codex spawns the MCP subprocess.

The Serena project config for this repo lives in `.serena/project.yml`.

### Odoo MCP

Run via `uvx mcp-server-odoo` (uvx at `/root/.local/bin/uvx`, env var `UVX_BIN`). No pre-installation needed — `uvx` fetches and runs the package on demand.

Registration is conditional on `ODOO_URL` being set. The following env vars are passed through from the host to the container by `scripts/run_with_truenas_mounts.sh` when set:

`ODOO_URL`, `ODOO_API_KEY`, `ODOO_USER`, `ODOO_PASSWORD`, `ODOO_DB`, `ODOO_LOCALE`, `ODOO_YOLO`

The Odoo registration is always fully refreshed on each container start (remove + re-add for Claude Code, rewrite for Codex config.toml) so changing credentials takes effect immediately on the next invocation.

---

## CLI Installation

### Codex CLI

Installed from npm: `npm install -g @openai/codex`

Auth: `codex login --device-auth` (ChatGPT subscription). Config stored in `~/.codex`.

### Usage Analyzers

Installed from npm: `npm install -g ccusage @ccusage/codex`

Binaries: `ccusage` (Claude Code usage), `ccusage-codex` (Codex usage).

### uv / uvx

Installed via `curl -LsSf https://astral.sh/uv/install.sh | sh`. Both `uv` and `uvx` land at `/root/.local/bin/`. Used to install Serena and to run Odoo MCP on demand.

---

## Wrapper Scripts

`bin/tnclaude`, `bin/tncodex`, `bin/tnccusage`, `bin/tncodexusage` — thin wrappers around `scripts/run_with_truenas_mounts.sh`. Each passes the appropriate mode flag and forwards remaining arguments.

Image auto-detection order: `TN_AI_CLI_IMAGE` → `AI_CLI_IMAGE` → local `docker-ai-cli-agents:latest` → `ghcr.io/<github-owner>/docker-ai-cli-agents:latest` from git remote.

---

## Logging

All logs go to stdout. The entrypoint uses `[TIMESTAMP] [LEVEL] message` format.

`AI_CLI_LOG_LEVEL=debug` enables verbose output (default: `info`).

Startup logs include: runtime mode, working directory, HOME, all tool versions, and MCP registration status.

---

## versions.json

Single source of truth for pinned tool versions. Updated by `scripts/update_versions.py`. Read by the Makefile to pass `--build-arg` values at build time.

```json
{
  "release_version": "0.1.x",
  "codex": { "source": "npm", "package": "@openai/codex", "version": "x.y.z" },
  "ccusage": { "source": "npm", "package": "ccusage", "version": "x.y.z" },
  "codex_usage": { "source": "npm", "package": "@ccusage/codex", "version": "x.y.z" }
}
```

---

## CI/CD

**Jenkins** runs a monthly scheduled job (4:00 AM America/Los_Angeles) that detects upstream version changes, updates `versions.json`, bumps the release version, commits, tags, and pushes to GitHub.

**GitHub Actions** triggers on tag push: builds the image, tags it `latest` and `<tag>`, and pushes to `ghcr.io/<owner>/docker-ai-cli-agents`.

Jenkins needs Docker Outside of Docker access (mounts `/var/run/docker.sock`). Additional Jenkins setup guidance is in `docs/jenkins.md`.

---

## Development Scripts

| Script | Purpose |
|---|---|
| `scripts/run_with_truenas_mounts.sh` | Run any mode with standard host mounts |
| `scripts/check_versions.sh` | Compare `versions.json` to upstream |
| `scripts/update_versions.py` | Update `versions.json`, optionally bump release version |
| `scripts/smoke_test.sh` | Bash syntax checks, JSON validation, optional container smoke tests |
