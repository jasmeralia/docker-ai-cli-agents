#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Update versions.json")
    parser.add_argument("--file", default="versions.json", help="Path to versions.json")
    parser.add_argument("--codex-version")
    parser.add_argument("--claude-version")
    parser.add_argument("--release-version")
    parser.add_argument("--bump-release", choices=["major", "minor", "patch"])
    return parser.parse_args()


def bump(version: str, part: str) -> str:
    major, minor, patch = [int(piece) for piece in version.split(".")]
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def main() -> int:
    args = parse_args()
    versions_path = Path(args.file)
    data = json.loads(versions_path.read_text())

    if args.codex_version:
        data["codex"]["version"] = args.codex_version
    if args.claude_version:
        data["claude"]["version"] = args.claude_version

    if args.release_version and args.bump_release:
        raise SystemExit("use either --release-version or --bump-release")

    if args.release_version:
        data["release_version"] = args.release_version
    elif args.bump_release:
        data["release_version"] = bump(data["release_version"], args.bump_release)

    versions_path.write_text(json.dumps(data, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
