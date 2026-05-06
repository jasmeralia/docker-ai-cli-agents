# Claude Code — Project Instructions

See **[AGENTS.md](AGENTS.md)** for full project context: purpose, architecture, entrypoint behavior, MCP server details, CI/CD pipeline, and developer entry points.

Key rules:
- Always update `README.md` and `AGENTS.md` when changing entrypoint behavior, env vars, MCP servers, scripts, or make targets.
- Run `make lint` before committing; fix any hadolint, shellcheck, or yamllint findings.
- Do not commit `versions.json`, `Jenkinsfile`, or `scripts/update_versions.py` — these have been removed.
