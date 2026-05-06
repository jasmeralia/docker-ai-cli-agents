#!/usr/bin/env python3
"""Read .mcp.json and register each MCP server into ~/.codex/config.toml.

This is an intentional, manual operation — not run automatically on container
start. Invoke via: docker run ... --register-mcp-json

Existing entries for the same server names are stripped and replaced so the
operation is idempotent. Uses proper TOML basic-string escaping for values and
validates server names and env keys against a strict allowlist so that
project-controlled input cannot inject TOML syntax into the persistent config.

Usage: register_mcp_json.py <mcp-json-path> <codex-config-path>
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path
from typing import Any

# TOML bare-key characters: letters, digits, hyphens, underscores.
# Env var keys additionally require a letter or underscore as the first char.
_NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")
_ENV_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def toml_str(value: Any) -> str:
    """Escape a value for use inside a TOML basic string (double-quoted)."""
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\b", "\\b")
        .replace("\f", "\\f")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )


def validate_servers(servers: dict[str, Any]) -> list[str]:
    """Return a list of validation error strings (empty means valid)."""
    errors: list[str] = []
    for name, server in servers.items():
        if not _NAME_RE.match(name):
            errors.append(
                f"server name {name!r} contains characters not allowed in a "
                "TOML bare key (only A-Z, a-z, 0-9, '-', '_' are permitted)"
            )
        env: dict[str, Any] = server.get("env", {})
        for key in env:
            if not _ENV_KEY_RE.match(key):
                errors.append(
                    f"env key {key!r} in server {name!r} is not a valid "
                    "identifier (must start with letter or '_', then "
                    "letters/digits/'_' only)"
                )
    return errors


def strip_server(config: str, name: str) -> str:
    """Remove [mcp_servers.NAME] and [mcp_servers.NAME.*] sections."""
    prefix = f"[mcp_servers.{name}]"
    subprefix = f"[mcp_servers.{name}."
    lines = config.split("\n")
    result: list[str] = []
    skip = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            skip = stripped == prefix or stripped.startswith(subprefix)
        if not skip:
            result.append(line)
    return "\n".join(result)


def build_server_block(name: str, server: dict[str, Any]) -> str:
    command: str = server.get("command", "")
    args: list[Any] = server.get("args", [])
    env: dict[str, Any] = server.get("env", {})

    args_toml = "[" + ", ".join(f'"{toml_str(a)}"' for a in args) + "]"
    block = (
        f"\n[mcp_servers.{name}]\n"
        f'command = "{toml_str(command)}"\n'
        f"args = {args_toml}\n"
        "startup_timeout_sec = 30\n"
        "tool_timeout_sec = 120\n"
        "enabled = true\n"
    )
    if env:
        block += f"\n[mcp_servers.{name}.env]\n"
        for k, v in env.items():
            block += f'{k} = "{toml_str(v)}"\n'
    return block


def main() -> int:
    if len(sys.argv) != 3:
        print(
            f"usage: {sys.argv[0]} <mcp-json-path> <codex-config-path>",
            file=sys.stderr,
        )
        return 1

    mcp_json_path = Path(sys.argv[1])
    codex_config_path = Path(sys.argv[2])

    data: dict[str, Any] = json.loads(mcp_json_path.read_text(encoding="utf-8"))
    servers: dict[str, Any] = data.get("mcpServers", {})
    if not servers:
        print("no mcpServers entries found; nothing to register", file=sys.stderr)
        return 0

    errors = validate_servers(servers)
    if errors:
        for err in errors:
            print(f"error: {err}", file=sys.stderr)
        return 1

    existing = ""
    if codex_config_path.exists():
        existing = codex_config_path.read_text(encoding="utf-8")

    for name in servers:
        existing = strip_server(existing, name)

    additions = "".join(build_server_block(name, srv) for name, srv in servers.items())
    content = existing.rstrip("\n") + "\n" + additions

    tmp = codex_config_path.with_suffix(".tmp")
    tmp.write_text(content, encoding="utf-8")
    shutil.move(str(tmp), codex_config_path)

    print(
        f"registered {len(servers)} MCP(s) from .mcp.json: {', '.join(servers)}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
