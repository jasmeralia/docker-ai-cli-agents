# docker-ai-cli-agents --- Project Context

## Developer Entry Points

Prefer the repo `Makefile` for routine validation and image creation:

- `make lint` runs the local smoke and syntax checks.
- `make lint SMOKE_IMAGE=docker-ai-cli-agents:test` also runs container
  smoke checks against a built image.
- `make build` builds the Docker image with pinned versions from
  `versions.json`.
- `make check-versions` prints the upstream version report used by
  automation.
- `make update-versions UPDATE_ARGS='...'` forwards arguments to
  `scripts/update_versions.py`, for example:
  `make update-versions UPDATE_ARGS='--codex-version 1.2.3 --bump-release patch'`
- Override the image tag with `IMAGE=...`, for example:
  `make build IMAGE=docker-ai-cli-agents:test`

## Purpose

This repository provides a Docker image containing both the **Codex
CLI** and **Claude CLI** so they can run easily in environments such as
**TrueNAS SCALE (Goldeye)** without modifying the host system.

The image is intended to be used as a developer utility container
capable of interacting with repositories and files stored on TrueNAS
datasets.

Primary goals:

-   Provide **one container image** containing both CLIs.
-   Support **subscription-based authentication** (ChatGPT login for
    Codex, Claude account login).
-   Work cleanly in **TrueNAS SCALE environments**.
-   Maintain **persistent CLI configuration directories** outside the
    container.
-   Provide automated **version detection, build, and publishing**
    pipelines.
-   Provide good **stdout logging** compatible with tools like
    **Dozzle**.

------------------------------------------------------------------------

# Repository Name

docker-ai-cli-agents

Published image:

ghcr.io/`<owner>`{=html}/docker-ai-cli-agents

Tags:

-   latest
-   `<repo release tag>`{=html}

Repository release version is independent of CLI versions.

CLI versions are included in commit messages.

Example commit:

chore: update CLI versions (codex 1.4.2, claude 0.12.1)

------------------------------------------------------------------------

# Container Runtime Layout

The container expects the following mounts when run in TrueNAS:

/mnt/myzstripe:/mnt/myzstripe\
/mnt/myzmirror:/mnt/myzmirror\
/etc:/mnt/truenas-etc:ro

Environment variable used for configuration location:

AI_CLI_HOME=/mnt/myzmirror/myzdset/morgan

Inside this directory the container expects:

${AI_CLI_HOME}/.codex${AI_CLI_HOME}/.claude

These directories store authentication and configuration files.

------------------------------------------------------------------------

# Entrypoint Behavior

The container entrypoint supports three flags:

--codex\
--claude\
--shell

If **no argument** is specified the container defaults to:

--codex

Examples:

docker run image --codex\
docker run image --claude\
docker run image --shell

Arguments after the selector are passed to the chosen CLI.

------------------------------------------------------------------------

# Base Image

Ubuntu LTS

Rationale:

-   Compatibility with Claude installer
-   Full development toolchain availability
-   Predictable environment

Installed tools include:

git\
gh\
jq\
yq\
ripgrep\
fd-find\
less\
tree\
python3\
pip\
nodejs\
npm\
curl\
wget\
bash\
zsh

------------------------------------------------------------------------

# CLI Installation

## Codex CLI

Installed from npm:

npm install -g @openai/codex

Authentication is done using ChatGPT subscription login:

codex login --device-auth

Configuration stored in:

\${AI_CLI_HOME}/.codex

------------------------------------------------------------------------

## Claude CLI

Installed via official installer:

curl -fsSL https://claude.ai/install.sh \| bash

Configuration stored in:

\${AI_CLI_HOME}/.claude

------------------------------------------------------------------------

# Logging

Logging is intentionally simple:

-   All logs go to stdout/stderr
-   Compatible with Docker log viewers such as Dozzle
-   Entry script prints startup diagnostics
-   Version numbers are logged at startup

Optional environment variable:

AI_CLI_LOG_LEVEL=info\|debug

------------------------------------------------------------------------

# versions.json

This file tracks the current CLI versions.

Example:

{ "release_version": "0.1.0", "codex": { "source": "npm", "package":
"@openai/codex", "version": "x.y.z" }, "claude": { "source":
"install.sh", "version": "x.y.z" } }

------------------------------------------------------------------------

# CI/CD Flow

Two systems participate in automation:

Jenkins\
GitHub Actions

------------------------------------------------------------------------

# Jenkins Responsibilities

Jenkins runs a **monthly scheduled job**.

Schedule:

4:00 AM America/Los_Angeles

Responsibilities:

1.  Checkout repository
2.  Read versions.json
3.  Detect latest Codex version from npm
4.  Detect latest Claude version using probe container
5.  If version change detected:
    -   update versions.json
    -   bump repo release version
    -   commit changes
    -   create Git tag
    -   push to GitHub

------------------------------------------------------------------------

# Claude Version Detection

Claude version detection runs inside a temporary container.

Process:

1.  Launch Ubuntu container
2.  Run Claude installer
3.  Execute:

claude --version

4.  Capture version output
5.  Return normalized version string

This avoids scraping external sources and guarantees the detected
version matches the installer.

------------------------------------------------------------------------

# Jenkins Docker Access

Jenkins runs inside Docker but **must launch other containers**.

Instead of Docker-in-Docker the design uses:

Docker Outside of Docker

Jenkins container mounts:

/var/run/docker.sock

Jenkins container must have permission to access the socket.

Typical methods:

-   run Jenkins container as root
-   match docker group GID
-   dynamically map group at startup

This allows Jenkins to run:

docker run\
docker build

without nested Docker daemons.

------------------------------------------------------------------------

# GitHub Actions

GitHub Actions build and publish the image.

Trigger:

push tag

Workflow:

1.  Checkout repository
2.  Build Docker image
3.  Tag image:

latest\
`<tag>`{=html}

4.  Push to:

ghcr.io/`<owner>`{=html}/docker-ai-cli-agents

OCI labels include:

repository URL\
git SHA\
repo release version\
codex version\
claude version

------------------------------------------------------------------------

# TrueNAS Deployment

A sample TrueNAS custom app YAML is included in the repo.

Features:

-   GHCR image reference
-   required dataset mounts
-   environment variables
-   interactive container support
-   minimal restart policy

Container is intended to be run **on-demand** rather than as a
persistent service.

------------------------------------------------------------------------

# Development Scripts

scripts/

check_versions.sh\
probe_claude_version.sh\
update_versions.py\
smoke_test.sh

These scripts support the Jenkins pipeline and local development.

------------------------------------------------------------------------

# Logging Expectations

Startup logs include:

selected runtime mode\
installed CLI versions\
mount verification\
environment variables

This ensures diagnostics are easily visible in Dozzle.

------------------------------------------------------------------------

# Future Extensions

Possible enhancements:

-   optional workspace mount configuration
-   support for additional AI CLIs
-   automatic health check command
-   additional developer tooling
