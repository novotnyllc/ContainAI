#!/usr/bin/env python3
"""
TOML config parser for ContainAI bash scripts.

Usage:
  Mode 1 - Simple key lookup:
    python3 parse-toml.py <config-file> <key-path>
    Example: python3 parse-toml.py config.toml agent.data_volume

  Mode 2 - Workspace path matching:
    python3 parse-toml.py <config-file> --workspace <path> --config-dir <dir>
    Example: python3 parse-toml.py config.toml --workspace /home/user/project --config-dir /home/user

Exit codes:
  0 - Success (or missing key/no match - outputs empty string)
  1 - Error (file not found, invalid TOML, missing Python dependencies)
"""

import os
import sys

# Python version handling: try tomllib (3.11+), fall back to tomli
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("Error: Python 3.11+ or tomli package required", file=sys.stderr)
        sys.exit(1)


def get_nested_value(data, key_path):
    """
    Get a nested value from a dict using dot notation.

    Args:
        data: The dictionary to search
        key_path: Dot-separated key path (e.g., "agent.data_volume")

    Returns:
        The value if found, None otherwise
    """
    keys = key_path.split(".")
    current = data
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def normalize_path(path):
    """
    Normalize a path: resolve to absolute, remove trailing slashes.

    Args:
        path: The path to normalize

    Returns:
        Normalized absolute path without trailing slash
    """
    # Use os.path.normpath to handle . and .. and multiple slashes
    normalized = os.path.normpath(os.path.abspath(path))
    # Remove trailing slash (normpath handles most cases, but be explicit)
    return normalized.rstrip("/") if normalized != "/" else "/"


def resolve_section_path(section_path, config_dir):
    """
    Resolve a workspace section path to an absolute path.

    Args:
        section_path: The path from [workspace."<path>"]
        config_dir: Directory containing the config file (for relative paths)

    Returns:
        Normalized absolute path
    """
    # Expand ~ to home directory
    expanded = os.path.expanduser(section_path)

    # If not absolute, resolve against config_dir
    if not os.path.isabs(expanded):
        resolved = os.path.join(config_dir, expanded)
    else:
        resolved = expanded

    return normalize_path(resolved)


def path_segment_matches(section_path, workspace_path):
    """
    Check if section_path matches workspace_path using path-segment boundary matching.

    A section path P matches workspace W if:
    - W equals P exactly, OR
    - W starts with P AND the character after P in W is "/"
    - Special case: "/" matches any absolute path

    Args:
        section_path: Normalized section path (candidate match)
        workspace_path: Normalized workspace path to match against

    Returns:
        True if matches, False otherwise

    Examples:
        /a/b matches /a/b      (exact)
        /a/b matches /a/b/c    (prefix with / boundary)
        /a/b does NOT match /a/bc (no segment boundary)
        / matches /anything    (root as catch-all)
    """
    if workspace_path == section_path:
        # Exact match
        return True

    # Special case: "/" matches any absolute path
    if section_path == "/" and workspace_path.startswith("/"):
        return True

    # Check prefix with segment boundary
    if workspace_path.startswith(section_path):
        # Ensure there's a / boundary after the prefix
        # section_path is already normalized (no trailing /)
        remainder = workspace_path[len(section_path) :]
        if remainder.startswith("/"):
            return True

    return False


def find_matching_workspace(data, workspace_path, config_dir):
    """
    Find the best matching workspace section using path-segment boundary matching.
    Longest match wins.

    Args:
        data: Parsed TOML data
        workspace_path: Absolute path to match
        config_dir: Directory containing the config file

    Returns:
        The matched workspace section dict, or None if no match
    """
    workspace_sections = data.get("workspace", {})
    if not isinstance(workspace_sections, dict):
        return None

    normalized_workspace = normalize_path(workspace_path)

    best_match = None
    best_match_len = -1

    for section_path, section_data in workspace_sections.items():
        if not isinstance(section_data, dict):
            continue

        resolved_path = resolve_section_path(section_path, config_dir)

        if path_segment_matches(resolved_path, normalized_workspace):
            # Longest match wins
            if len(resolved_path) > best_match_len:
                best_match = section_data
                best_match_len = len(resolved_path)

    return best_match


def simple_key_lookup(config_file, key_path):
    """
    Mode 1: Simple key lookup.

    Args:
        config_file: Path to TOML config file
        key_path: Dot-separated key path

    Returns:
        0 on success, 1 on error
    """
    try:
        with open(config_file, "rb") as f:
            data = tomllib.load(f)
    except FileNotFoundError:
        print(f"Error: File not found: {config_file}", file=sys.stderr)
        return 1
    except tomllib.TOMLDecodeError as e:
        print(f"Error: Invalid TOML in {config_file}: {e}", file=sys.stderr)
        return 1

    value = get_nested_value(data, key_path)
    if value is not None:
        print(value, end="")
    # Missing key: empty stdout, exit 0

    return 0


def workspace_matching(config_file, workspace_path, config_dir):
    """
    Mode 2: Workspace path matching.

    Finds the best matching [workspace."<path>"] section and returns its data_volume.
    Falls back to [agent].data_volume if no match.
    Returns empty string if no fallback exists.

    Args:
        config_file: Path to TOML config file
        workspace_path: Absolute workspace path to match
        config_dir: Directory containing the config file

    Returns:
        0 on success, 1 on error
    """
    try:
        with open(config_file, "rb") as f:
            data = tomllib.load(f)
    except FileNotFoundError:
        print(f"Error: File not found: {config_file}", file=sys.stderr)
        return 1
    except tomllib.TOMLDecodeError as e:
        print(f"Error: Invalid TOML in {config_file}: {e}", file=sys.stderr)
        return 1

    # Try workspace matching first
    matched_section = find_matching_workspace(data, workspace_path, config_dir)

    if matched_section is not None:
        data_volume = matched_section.get("data_volume")
        if data_volume is not None:
            print(data_volume, end="")
            return 0

    # Fall back to [agent].data_volume
    agent_volume = get_nested_value(data, "agent.data_volume")
    if agent_volume is not None:
        print(agent_volume, end="")
        return 0

    # No match and no fallback: empty stdout, exit 0
    return 0


def print_usage():
    """Print usage information."""
    print(__doc__, file=sys.stderr)


def main():
    """Main entry point."""
    args = sys.argv[1:]

    if len(args) < 2:
        print_usage()
        return 1

    config_file = args[0]

    # Check for workspace matching mode
    if args[1] == "--workspace":
        # Mode 2: Workspace matching
        # Expected: <config-file> --workspace <path> --config-dir <dir>
        if len(args) < 5 or args[3] != "--config-dir":
            print(
                "Error: --workspace requires --config-dir",
                file=sys.stderr,
            )
            print_usage()
            return 1

        workspace_path = args[2]
        config_dir = args[4]
        return workspace_matching(config_file, workspace_path, config_dir)
    else:
        # Mode 1: Simple key lookup
        # Expected: <config-file> <key-path>
        key_path = args[1]
        return simple_key_lookup(config_file, key_path)


if __name__ == "__main__":
    sys.exit(main())
