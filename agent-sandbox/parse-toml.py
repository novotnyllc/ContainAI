#!/usr/bin/env python3
"""Parse ContainAI TOML config. Requires Python 3.11+ (tomllib)."""
import sys

try:
    import tomllib
except ImportError:
    print("Error: Python 3.11+ required (tomllib not available)", file=sys.stderr)
    sys.exit(1)

import json
from pathlib import Path


def find_workspace(config: dict, workspace: str) -> dict | None:
    """Find workspace with longest matching path (segment boundary)."""
    workspace = Path(workspace).resolve()
    workspaces = config.get("workspace", {})

    best_match, best_len = None, 0
    for path_str, section in workspaces.items():
        cfg_path = Path(path_str)
        if not cfg_path.is_absolute():
            continue
        try:
            workspace.relative_to(cfg_path)
            if len(str(cfg_path)) > best_len:
                best_match, best_len = section, len(str(cfg_path))
        except ValueError:
            pass
    return best_match


def main():
    if len(sys.argv) < 3:
        print("Usage: parse-toml.py <config> <workspace>", file=sys.stderr)
        sys.exit(1)

    try:
        with open(sys.argv[1], "rb") as f:
            config = tomllib.load(f)
    except FileNotFoundError:
        print(f"Error: Config file not found: {sys.argv[1]}", file=sys.stderr)
        sys.exit(1)
    except tomllib.TOMLDecodeError as e:
        print(f"Error: Invalid TOML: {e}", file=sys.stderr)
        sys.exit(1)

    ws = find_workspace(config, sys.argv[2])
    agent = config.get("agent", {})
    default_excludes = config.get("default_excludes", [])

    print(json.dumps({
        "data_volume": ws.get("data_volume") if ws else agent.get("data_volume", "sandbox-agent-data"),
        "excludes": list(set(default_excludes + (ws.get("excludes", []) if ws else [])))
    }))


if __name__ == "__main__":
    main()
