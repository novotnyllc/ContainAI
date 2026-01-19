#!/usr/bin/env python3
"""Parse ContainAI TOML config. Requires Python 3.11+ (tomllib)."""
import argparse
import json
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    print("Error: Python 3.11+ required (tomllib not available)", file=sys.stderr)
    sys.exit(1)


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


def validate_single_line(value: str, field_name: str) -> str:
    """
    Validate that a string value is single-line (no embedded newlines).

    Args:
        value: String value to validate
        field_name: Field name for error message

    Returns:
        The value if valid

    Raises:
        ValueError: If value contains newlines
    """
    if "\n" in value or "\r" in value:
        raise ValueError(f"{field_name} must be single-line (no embedded newlines)")
    return value


def main():
    parser = argparse.ArgumentParser(
        description="Parse ContainAI TOML config file"
    )
    parser.add_argument(
        "config",
        help="Path to config.toml file"
    )
    parser.add_argument(
        "workspace",
        help="Workspace path for matching"
    )
    args = parser.parse_args()

    config_path = args.config
    workspace = args.workspace

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

    # Validate data_volume is single-line (required for line-based parsing)
    try:
        validate_single_line(data_volume, "data_volume")
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    # Stable de-dupe preserving order (dict.fromkeys preserves insertion order)
    combined_excludes = default_excludes + ws_excludes
    # Filter to only single-line strings and dedupe
    seen = {}
    for item in combined_excludes:
        if isinstance(item, str) and item not in seen:
            try:
                validate_single_line(item, "exclude pattern")
                seen[item] = True
            except ValueError:
                # Skip excludes with embedded newlines
                print(f"Warning: Skipping exclude with embedded newline: {repr(item)}", file=sys.stderr)
    excludes = list(seen.keys())

    # Output compact JSON (no spaces) for reliable bash parsing
    print(json.dumps({
        "data_volume": data_volume,
        "excludes": excludes
    }, separators=(",", ":")))


if __name__ == "__main__":
    main()
