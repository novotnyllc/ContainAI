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
    """
    Find workspace with longest matching path (segment boundary).

    Only absolute paths in workspace sections are matched; relative paths are skipped.

    Args:
        config: Parsed TOML config dict
        workspace: Workspace path to match

    Returns:
        Matched workspace section or None
    """
    workspace_path = Path(workspace).resolve()
    workspaces = config.get("workspace", {})

    if not isinstance(workspaces, dict):
        return None

    best_match = None
    best_segments = 0

    for path_str, section in workspaces.items():
        if not isinstance(section, dict):
            continue

        cfg_path = Path(path_str)

        # Skip relative paths (spec: "Absolute paths only")
        if not cfg_path.is_absolute():
            continue

        cfg_path = cfg_path.resolve()

        # Check if workspace is under cfg_path (segment boundary match)
        try:
            workspace_path.relative_to(cfg_path)
            # Use segment count for longest match (more specific = more segments)
            num_segments = len(cfg_path.parts)
            if num_segments > best_segments:
                best_match, best_segments = section, num_segments
        except ValueError:
            pass

    return best_match


def main():
    # Check for --format=lines option
    format_lines = "--format=lines" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--format=")]

    if len(args) < 2:
        print("Usage: parse-toml.py [--format=lines] <config> <workspace>", file=sys.stderr)
        sys.exit(1)

    config_path = args[0]
    workspace = args[1]

    try:
        with open(config_path, "rb") as f:
            config = tomllib.load(f)
    except FileNotFoundError:
        print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)
    except tomllib.TOMLDecodeError as e:
        print(f"Error: Invalid TOML: {e}", file=sys.stderr)
        sys.exit(1)

    ws = find_workspace(config, workspace)
    agent = config.get("agent", {})
    default_excludes = config.get("default_excludes", [])

    # Validate types
    if not isinstance(default_excludes, list):
        default_excludes = []
    if not isinstance(agent, dict):
        agent = {}

    # Get workspace excludes if ws exists
    ws_excludes = []
    if ws:
        ws_excludes = ws.get("excludes", [])
        if not isinstance(ws_excludes, list):
            ws_excludes = []

    # Fallback chain for data_volume:
    # 1. workspace.data_volume (if ws exists and has it)
    # 2. agent.data_volume
    # 3. default
    data_volume = None
    if ws:
        data_volume = ws.get("data_volume")
    if not data_volume:
        data_volume = agent.get("data_volume", "sandbox-agent-data")

    # Stable de-dupe preserving order (dict.fromkeys preserves insertion order)
    combined_excludes = default_excludes + ws_excludes
    # Filter to only strings and dedupe
    seen = {}
    for item in combined_excludes:
        if isinstance(item, str) and item not in seen:
            seen[item] = True
    excludes = list(seen.keys())

    # Output format
    if format_lines:
        # Line-based format for bash: VOLUME=<vol> then one exclude per line
        print(f"VOLUME={data_volume}")
        for exc in excludes:
            print(exc)
    else:
        # Compact JSON (no spaces) for reliable bash parsing
        print(json.dumps({
            "data_volume": data_volume,
            "excludes": excludes
        }, separators=(",", ":")))


if __name__ == "__main__":
    main()
