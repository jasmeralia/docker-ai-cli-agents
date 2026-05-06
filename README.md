# docker-ai-cli-agents

Docker image and automation for running Claude Code and Codex CLI in a sandboxed utility container, with Serena MCP and optional Odoo MCP pre-configured for both agents.

## What this repo includes

- A Docker image built on `node:20` with Claude Code, Codex CLI, and usage analyzers installed from npm
- [Serena MCP](https://github.com/oraios/serena) — code intelligence server, always registered for both agents on startup
- [Odoo MCP](https://github.com/ivnvxd/mcp-server-odoo) — Odoo ERP integration, configured once on the host via bind-mounted config files
- A mode-selecting entrypoint for `--claude`, `--codex`, `--ccusage`, `--codexusage`, `--register-mcp-json`, or `--shell`
- `package.json` + `requirements.txt` as the source of truth for tool versions
- Dependabot tracking npm, pip, GitHub Actions, and Docker base image
- Auto-merge for Dependabot PRs (with CI gate) and automatic patch tagging and image publish on every master merge

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
docker run --rm -it image --register-mcp-json
docker run --rm -it image --shell
```

Arguments after the mode selector are passed through to the selected CLI or shell.

## Wrapper scripts

The `bin/` directory contains thin wrappers around `scripts/run_with_truenas_mounts.sh` that:

- Bind-mount the current host directory to `/workdir`
- Bind-mount `~/.claude`, `~/.claude.json`, `~/.codex`, and `~/.config/gh` from the host so config and auth persist between container runs
- Auto-detect the image reference and pull the latest image automatically when no tag is pinned
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

The `--tag` flag (or `TN_AI_CLI_TAG` env var) replaces the tag portion of the detected image, leaving the registry and repo path unchanged. When a tag override is set, the image is not automatically pulled (assumed pinned intentionally).

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

### Quick setup

Authenticate interactively — the browser-based OAuth flow requires no manual token creation:

```bash
gh auth login
```

Follow the prompts to authenticate via the browser. Verify afterwards:

```bash
gh auth status
```

### Tighter scope (recommended for yolo modes)

The OAuth token from `gh auth login` grants broad repository access. `gh auth login --scopes` can customize classic OAuth scopes, but classic scopes have no read-only contents option — `repo` is all-or-nothing for repository access. The per-resource permission levels (Contents: Read only, Pull requests: Read+Write, etc.) are only available via fine-grained PATs, which must be created through the GitHub web UI.

For narrower control — particularly blocking the agent from merging PRs or pushing code — create a fine-grained PAT at [github.com/settings/tokens](https://github.com/settings/tokens) with the following permissions. Granting **Contents: Read only** is the critical constraint — PR merges require Contents write, so this blocks the agent from merging while leaving PR creation and editing intact.

| Permission | Level | Effect |
|---|---|---|
| Metadata | Read | Required; repository metadata |
| Contents | **Read only** | Read code; blocks pushes and merges |
| Pull requests | Read and write | Create, edit, review, comment on PRs |
| Issues | Read and write | Read and comment on issues |
| Actions | Read | Check CI/workflow status |
| Commit statuses | Read | Check PR status checks |

Then authenticate with the token:

```bash
gh auth login --with-token <<< "github_pat_..."
```

## MCP servers

### Serena (always active)

[Serena](https://github.com/oraios/serena) provides code-intelligence tools (symbol search, semantic editing, diagnostics). It is registered unconditionally for both Claude Code and Codex on every container start. No configuration required.

Serena uses [solidlsp](https://github.com/oraios/solidlsp) to drive language servers. Whether a given language works depends on what's available in the image:

**Works out of the box** — LSP binary is auto-downloaded or provided by Node/Python already in the image:
- Bash/shell (`bash-language-server` via npm)
- TypeScript / JavaScript (`typescript-language-server` via npm)
- Python (pyright, auto-downloaded; or jedi/ty if pre-installed)
- JSON, YAML, TOML (auto-downloaded LSPs)
- Terraform, Vue, and others with npm-distributed LSPs

**Requires adding the runtime to the image** — Serena knows how to drive these LSPs but the compiler/toolchain is not included:
- Go (needs `gopls`), Rust (needs `rust-analyzer`), Java/Kotlin (needs JDK + jdtls), Ruby, C/C++ (clangd), and most other compiled languages

To add a language, install its toolchain in the Dockerfile and verify Serena can find the LSP binary at `/workdir` startup.

### Project `.mcp.json` (Codex manual registration)

Claude Code natively loads `.mcp.json` from the project root. Codex has no equivalent — its MCP config is global (`~/.codex/config.toml`). The image includes a helper script to bridge the gap when you intentionally want to sync a project's `.mcp.json` into the Codex global config:

```bash
docker run --rm \
  --mount type=bind,src="$(pwd)",dst=/workdir \
  --mount type=bind,src="${HOME}/.codex",dst=/root/.codex \
  ghcr.io/<owner>/docker-ai-cli-agents:latest --register-mcp-json
```

This reads `/workdir/.mcp.json`, validates server names and env keys, strips any existing entries for the same names, and appends the new blocks. It is idempotent and safe to re-run after editing `.mcp.json`. Server names and env keys are validated against a strict allowlist (letters, digits, `-`, `_`) before any write occurs; malformed input is rejected with an error rather than written partially.

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
| `make lint` | Run all linters (hadolint, shellcheck, yamllint, ruff, mypy, pylint) and smoke tests |
| `make lint SMOKE_IMAGE=docker-ai-cli-agents:test` | Also run container smoke tests |
| `make build` | Build the image (release version from latest git tag) |
| `make build IMAGE=docker-ai-cli-agents:test` | Build with a custom tag |

## Version management

Tool versions are pinned in:

- `package.json` — npm tools (`@anthropic-ai/claude-code`, `@openai/codex`, `ccusage`, `@ccusage/codex`)
- `requirements.txt` — Python tools (`serena-agent`)

<<<<<<< HEAD
Dependabot monitors both files weekly and raises PRs automatically. Dependabot PRs are auto-approved and auto-merged once CI (`make lint` + `make build`) passes. Each merge to master triggers a patch tag bump and immediately builds and publishes a new image to GHCR in the same workflow run.
=======
Dependabot monitors both files weekly and raises PRs automatically. Dependabot PRs are auto-merged once CI (`make lint` + `make build`) passes. Each merge to master bumps the patch tag and immediately builds and publishes a new image to GHCR.
>>>>>>> 43948b6 (docs: clean up README.md)

To pin or roll back to a specific release, use the image tag:

```bash
bin/tnclaude --tag v0.1.2
```
