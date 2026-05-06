# docker-ai-cli-agents

Docker image and automation for running Claude Code and Codex CLI in a sandboxed utility container, with Serena MCP and optional Odoo MCP pre-configured for both agents.

## What this repo includes

- A Docker image built on `node:20` with Claude Code, Codex CLI, and usage analyzers installed from npm
- [Serena MCP](https://github.com/oraios/serena) — code intelligence server, always registered for both agents on startup
- [Odoo MCP](https://github.com/ivnvxd/mcp-server-odoo) — Odoo ERP integration, registered automatically when `ODOO_URL` is set
- A mode-selecting entrypoint for `--claude`, `--codex`, `--ccusage`, `--codexusage`, or `--shell`
- `package.json` + `requirements.txt` as the source of truth for tool versions
- Dependabot tracking npm, pip, GitHub Actions, and Docker base image
- Auto-merge for Dependabot PRs (with CI gate) and automatic patch tag on every master merge
- GitHub Actions for image build and publish on tag push
- Sample TrueNAS custom app configuration

## Build

```bash
make build
```

Or manually:

```bash
docker build \
  --build-arg REPO_RELEASE_VERSION="$(git describe --tags --abbrev=0 | sed 's/^v//')" \
  -t docker-ai-cli-agents:latest .
```

Tool versions come from `package.json` (npm) and `requirements.txt` (pip) baked into the image via `npm ci` and `uv tool install`.

## Run

Default mode is `--claude`:

```bash
docker run --rm -it \
  --mount type=bind,src="$(pwd)",dst=/workdir \
  --mount type=bind,src="${HOME}/.claude",dst=/root/.claude \
  --mount type=bind,src="${HOME}/.claude.json",dst=/root/.claude.json \
  --mount type=bind,src="${HOME}/.codex",dst=/root/.codex \
  --mount type=bind,src="${HOME}/.config/gh",dst=/root/.config/gh \
  --workdir /workdir \
  -e HOME=/root \
  ghcr.io/<owner>/docker-ai-cli-agents:latest
```

Explicit modes:

```bash
docker run --rm -it image --claude-safe    # file edits auto-approved; shell commands prompted
docker run --rm -it image --claude-yolo    # no prompts (--dangerously-skip-permissions)
docker run --rm -it image --codex-safe     # trusted read-only commands auto-approved; others prompted
docker run --rm -it image --codex-yolo     # no prompts (--dangerously-bypass-approvals-and-sandbox)
docker run --rm -it image --claude         # fully prompted (all operations require approval)
docker run --rm -it image --codex          # fully prompted (all operations require approval)
docker run --rm -it image --ccusage
docker run --rm -it image --codexusage
docker run --rm -it image --shell
```

The Docker socket is mounted by default in all non-yolo modes (when `/var/run/docker.sock` exists on the host). Set `SANDBOX_DOCKER=0` to disable. The `-yolo` scripts always disable the socket and suppress all prompts.

Arguments after the mode selector are passed through to the selected CLI or shell.

## Wrapper scripts

The `bin/` directory contains `tnclaude`, `tncodex`, `tnccusage`, and `tncodexusage`. These are thin wrappers around `scripts/run_with_truenas_mounts.sh` that:

- Bind-mount the current host directory to `/workdir`
- Bind-mount `~/.claude`, `~/.claude.json`, `~/.codex`, and `~/.config/gh` from the host so config and auth persist between container runs
- Auto-detect the image reference (see below)
- Forward all arguments to the selected mode

```bash
bin/tnclaude          # file edits auto-approved, shell commands prompted; socket mounted by default
bin/tnclaude-yolo     # no prompts; socket never mounted
bin/tncodex           # trusted read-only commands auto-approved, others prompted; socket mounted by default
bin/tncodex-yolo      # no prompts; socket never mounted
bin/tnccusage --help
bin/tncodexusage --help
```

The Docker socket (`/var/run/docker.sock`) is mounted by default when it exists on the host. Set `SANDBOX_DOCKER=0` to disable for a single run. The `-yolo` scripts hard-disable the socket and suppress all prompts — use them for fully-autonomous delegation where Docker access is not needed.

To call without `bin/`, add the repo root or `bin/` to your `PATH`, or symlink the scripts into a directory already on your `PATH`.

**Image tag override** — run a specific release instead of `latest`:

```bash
bin/tnclaude --tag v0.1.3
TN_AI_CLI_TAG=v0.1.3 bin/tnclaude
```

The `--tag` flag (or `TN_AI_CLI_TAG` env var) replaces the tag portion of the detected image, leaving the registry and repo path unchanged.

**Image detection order** (first match wins):

1. `TN_AI_CLI_IMAGE` env var (full image reference including tag)
2. `AI_CLI_IMAGE` env var (full image reference including tag)
3. Local `docker-ai-cli-agents:latest` if present
4. `ghcr.io/<github-owner>/docker-ai-cli-agents:latest` parsed from the git remote

**Optional flags:**

- `SANDBOX_DOCKER=0` — disables the Docker socket mount (mounted by default when present)
- `AI_CLI_LOG_LEVEL=debug` — enables verbose startup logging

## GitHub authentication

`~/.config/gh` is bind-mounted into all container modes, giving the agent access to the host GitHub CLI auth token. In yolo modes this is unsandboxed — the agent can use `gh` without prompts to read or write any resource the token allows.

**Recommended mitigation: use a fine-grained PAT with narrow scope.**

Create a fine-grained personal access token at [github.com/settings/tokens](https://github.com/settings/tokens) with the following repository permissions. Granting **Contents: Read only** (not Write) is the critical constraint — PR merges require Contents write, so this blocks the agent from merging while leaving PR creation and editing intact.

| Permission | Level | Effect |
|---|---|---|
| Metadata | Read | Required; repository metadata |
| Contents | **Read only** | Read code; blocks pushes and merges |
| Pull requests | Read and write | Create, edit, review, comment on PRs |
| Issues | Read and write | Read and comment on issues |
| Actions | Read | Check CI/workflow status |
| Commit statuses | Read | Check PR status checks |

Authenticate with the fine-grained token:

```bash
gh auth login --with-token <<< "github_pat_..."
# or interactively:
gh auth login
```

Verify the active token and its scopes:

```bash
gh auth status
```

## MCP servers

### Serena (always active)

[Serena](https://github.com/oraios/serena) provides code-intelligence tools (symbol search, semantic editing, diagnostics). It is registered unconditionally for both Claude Code and Codex on every container start. No configuration required.

### Odoo (manual host configuration)

[Odoo MCP](https://github.com/ivnvxd/mcp-server-odoo) is not injected by the entrypoint. Configure it once directly on the host in the bind-mounted config files — it will be available in every subsequent container run.

**For Codex** — add to `~/.codex/config.toml`:

```toml
[mcp_servers.odoo]
command = "uvx"
args = ["mcp-server-odoo"]
startup_timeout_sec = 30
tool_timeout_sec = 120
enabled = true

[mcp_servers.odoo.env]
ODOO_URL = "https://mycompany.odoo.com"
ODOO_API_KEY = "your-api-key-here"
# ODOO_DB = "mycompany"       # required only when db listing is restricted
# ODOO_LOCALE = "fr_FR"
```

**For Claude Code** — run once on the host:

```bash
claude mcp add --scope user \
  --env ODOO_URL=https://mycompany.odoo.com \
  --env ODOO_API_KEY=your-api-key-here \
  odoo -- uvx mcp-server-odoo
```

> **Security note:** Credentials are stored in `~/.claude` and `~/.codex` on the host filesystem. Restrict permissions on those directories and avoid committing them to version control.

## Claude Code plugin: Codex

The [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) plugin is baked into the image and loaded automatically for all Claude Code modes via `--plugin-dir`. It provides `/codex:*` slash commands that let Claude delegate tasks to and review code with Codex directly from a Claude Code session.

## Scripts

- `scripts/run_with_truenas_mounts.sh` — run any mode with standard host mounts (used by `bin/tn*`)
- `scripts/smoke_test.sh` — lightweight local checks and optional container smoke tests

## Make targets

| Target | Description |
|---|---|
| `make lint` | Run hadolint, shellcheck, yamllint, and smoke tests |
| `make lint SMOKE_IMAGE=docker-ai-cli-agents:test` | Also run container smoke tests |
| `make build` | Build the image (release version from latest git tag) |
| `make build IMAGE=docker-ai-cli-agents:test` | Build with a custom tag |

## Version management

Tool versions are pinned in:

- `package.json` — npm tools (`@anthropic-ai/claude-code`, `@openai/codex`, `ccusage`, `@ccusage/codex`)
- `requirements.txt` — Python tools (`serena-agent`)

Dependabot monitors both files weekly and raises PRs automatically. Dependabot PRs are auto-approved and auto-merged once CI (`make lint` + `make build`) passes. Each merge to master triggers a patch tag bump, which triggers a new image publish to GHCR.

To pin or roll back to a specific release, use the image tag:

```bash
bin/tnclaude --tag v0.1.2
```
