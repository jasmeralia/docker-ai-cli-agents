# docker-ai-cli-agents — Project Context

## Developer Entry Points

Prefer the repo `Makefile` for routine validation and image creation:

- `make lint` — runs hadolint, shellcheck, yamllint, and the smoke tests
- `make lint SMOKE_IMAGE=docker-ai-cli-agents:test` — also runs container smoke checks
- `make build` — builds the Docker image (derives release version from the latest git tag)
- `make build IMAGE=docker-ai-cli-agents:test` — build with a custom tag

When making code changes, always update `README.md` and `AGENTS.md` to reflect what changed — entrypoint behavior, new env vars, new MCP servers, changed script paths, new make targets, etc. Documentation is part of the changeset, not a follow-up task.

---

## Purpose

This repository provides a Docker image containing Claude Code (`claude`) and Codex CLI (`codex`) so they can run in sandboxed environments — originally designed for TrueNAS SCALE but usable anywhere Docker runs.

Primary goals:

- Provide one container image with both CLIs plus Serena MCP and Odoo MCP support
- Support subscription-based authentication (Claude account for Claude Code, ChatGPT subscription for Codex)
- Maintain persistent CLI configuration directories outside the container via bind mounts
- Provide automated version detection via Dependabot, CI gating, and auto-tagging on master push
- Provide clean stdout logging compatible with tools like Dozzle

---

## Base Image

`node:20`

Matches Anthropic's own devcontainer base. All npm tools (Claude Code, Codex, ccusage, ccusage-codex) are installed from `package.json` via `npm ci --prefix /opt/npm-tools` for reproducible builds. Dependabot tracks the npm ecosystem and raises PRs when new versions are available.

---

## Version Management

Tool versions are tracked in two manifest files:

- `package.json` / `package-lock.json` — npm tools: `@anthropic-ai/claude-code`, `@openai/codex`, `ccusage`, `@ccusage/codex`
- `requirements.txt` — Python tools: `serena-agent`

Dependabot monitors both files (npm and pip ecosystems) and raises PRs automatically. PRs from `dependabot[bot]` are auto-approved and auto-merged once CI passes. Each merge to master triggers the auto-tag workflow, which bumps the patch version and pushes a `v*` tag, which triggers the publish workflow to build and push the Docker image.

The release version is derived from the latest git tag at build time — no separate `versions.json` is needed.

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
| `--claude` | `claude` (all prompts enabled) |
| `--claude-safe` | `claude --permission-mode acceptEdits` (file ops auto-approved, shell prompted) |
| `--claude-yolo` | `claude --dangerously-skip-permissions` (no prompts) |
| `--codex` | `codex` (all prompts enabled) |
| `--codex-safe` | `codex -a untrusted` (trusted read-only commands auto-approved, others prompted) |
| `--codex-yolo` | `codex --dangerously-bypass-approvals-and-sandbox` (no prompts) |
| `--ccusage` | `ccusage` |
| `--codexusage` | `ccusage-codex` |
| `--shell` | `$SHELL` (bash) |

The Docker socket is mounted by default (when `/var/run/docker.sock` exists). Set `SANDBOX_DOCKER=0` to disable. The `-yolo` scripts always set `SANDBOX_DOCKER=0` to prevent combining unfettered agent access with host Docker access.

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

Installed via `uv tool install -p 3.13` with the version pinned in `requirements.txt`. Binary at `/root/.local/bin/serena` (env var `SERENA_BIN`).

Registered for Claude Code with `--context=claude-code` and for Codex with `--context=codex`. Both use `--project-from-cwd` so Serena detects the project from `/workdir`. Codex registration also sets `cwd = "/workdir"` to ensure the working directory is correct when Codex spawns the MCP subprocess.

The Serena project config for this repo lives in `.serena/project.yml`.

### Odoo MCP

Run via `uvx mcp-server-odoo` (uvx at `/root/.local/bin/uvx`, env var `UVX_BIN`). No pre-installation needed — `uvx` fetches and runs the package on demand.

Registration is conditional on `ODOO_URL` being set. The following env vars are passed through from the host to the container by `scripts/run_with_truenas_mounts.sh` when set:

`ODOO_URL`, `ODOO_API_KEY`, `ODOO_USER`, `ODOO_PASSWORD`, `ODOO_DB`, `ODOO_LOCALE`, `ODOO_YOLO`

The Odoo registration is always fully refreshed on each container start (remove + re-add for Claude Code, rewrite for Codex config.toml) so changing credentials takes effect immediately on the next invocation.

---

## CLI Installation

All npm tools are installed via `npm ci --prefix /opt/npm-tools` from `package.json`. The binaries land in `/opt/npm-tools/node_modules/.bin/` which is added to `PATH`.

| Tool | npm Package |
|---|---|
| `claude` | `@anthropic-ai/claude-code` |
| `codex` | `@openai/codex` |
| `ccusage` | `ccusage` |
| `ccusage-codex` | `@ccusage/codex` |

Serena (`serena`) is installed via `uv tool install` from `requirements.txt`. The `uvx` binary is used to run Odoo MCP on demand.

---

## Wrapper Scripts

`bin/tnclaude`, `bin/tncodex`, `bin/tnccusage`, `bin/tncodexusage` — thin wrappers around `scripts/run_with_truenas_mounts.sh`. Mount the Docker socket by default (when present). Claude auto-approves file edits but prompts for shell commands; Codex auto-approves only trusted read-only commands and prompts for everything else.

`bin/tnclaude-yolo`, `bin/tncodex-yolo` — set `SANDBOX_DOCKER=0` unconditionally (no Docker socket) and suppress all prompts. Intended for fully-autonomous delegation where host Docker access is not needed.

`scripts/run_with_truenas_mounts.sh` accepts `--tag <image-tag>` after the mode selector to override the image tag. The `TN_AI_CLI_TAG` env var does the same.

Image auto-detection order: `TN_AI_CLI_IMAGE` → `AI_CLI_IMAGE` → local `docker-ai-cli-agents:latest` → `ghcr.io/<github-owner>/docker-ai-cli-agents:latest` from git remote.

---

## Logging

All logs go to stdout. The entrypoint uses `[TIMESTAMP] [LEVEL] message` format.

`AI_CLI_LOG_LEVEL=debug` enables verbose output (default: `info`).

Startup logs include: runtime mode, working directory, HOME, all tool versions, and MCP registration status.

---

## CI/CD

**Dependabot** monitors `package.json` (npm), `requirements.txt` (pip), GitHub Actions, and the Docker base image. It raises weekly PRs for updates.

**dependabot-auto-merge** workflow auto-approves and enables auto-merge for Dependabot PRs once CI passes.

**ci** workflow runs `make lint` and `make build` on every PR to master, acting as the CI gate for auto-merge.

**auto-tag** workflow triggers on every push to master: bumps the patch version of the latest semver tag and pushes a new `v*` tag.

**publish** workflow triggers on `v*` tag push: builds the image, tags it `latest` and `<tag>`, and pushes to `ghcr.io/<owner>/docker-ai-cli-agents`. The release version is derived from the git tag (`GITHUB_REF_NAME` with `v` prefix stripped).

---

## Development Scripts

| Script | Purpose |
|---|---|
| `scripts/run_with_truenas_mounts.sh` | Run any mode with standard host mounts |
| `scripts/smoke_test.sh` | Bash syntax checks and optional container smoke tests |
