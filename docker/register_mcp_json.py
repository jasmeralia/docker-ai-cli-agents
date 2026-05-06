#!/usr/bin/env python3
"""Read .mcp.json and register each MCP server into ~/.codex/config.toml.

Existing entries for the same server names are stripped and replaced so
running this on every container start is idempotent and picks up config
changes. Uses proper TOML basic-string escaping to avoid corrupting the
config with credentials that contain quotes or backslashes.

Usage: register_mcp_json.py <mcp-json-path> <codex-config-path>
"""

import json
import shutil
import sys
from pathlib import Path


def toml_str(value: str) -> str:
    """Escape a string for use inside a TOML basic string (double-quoted)."""
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


def build_server_block(name: str, server: dict) -> str:
    command = server.get("command", "")
    args = server.get("args", [])
    env: dict = server.get("env", {})

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
        print(f"usage: {sys.argv[0]} <mcp-json-path> <codex-config-path>", file=sys.stderr)
        return 1

    mcp_json_path = Path(sys.argv[1])
    codex_config_path = Path(sys.argv[2])

    data = json.loads(mcp_json_path.read_text())
    servers: dict = data.get("mcpServers", {})
    if not servers:
        return 0

    existing = codex_config_path.read_text() if codex_config_path.exists() else ""

    for name in servers:
        existing = strip_server(existing, name)

    additions = "".join(build_server_block(name, srv) for name, srv in servers.items())
    content = existing.rstrip("\n") + "\n" + additions

    tmp = codex_config_path.with_suffix(".tmp")
    tmp.write_text(content)
    shutil.move(str(tmp), codex_config_path)

    print(
        f"registered {len(servers)} MCP(s) from .mcp.json: {', '.join(servers)}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
