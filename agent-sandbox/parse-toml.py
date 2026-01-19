#!/usr/bin/env python3
"""
parse-toml.py - Minimal TOML config parser for shell script consumption.

Provides a CLI interface for reading TOML configuration values, suitable
for calling from shell scripts that need to access config settings.

Usage:
    python3 parse-toml.py --file config.toml --key agent.data_volume
    python3 parse-toml.py --file config.toml --json
    python3 parse-toml.py --file config.toml --exists agent.data_volume
"""
import argparse
import json
import sys
from pathlib import Path

# Python 3.11+ has tomllib in stdlib, fallback to toml package for older versions
try:
    import tomllib

    def load_toml(path: Path) -> dict:
        """Load TOML file using tomllib (Python 3.11+)."""
        with open(path, "rb") as f:
            return tomllib.load(f)

except ImportError:
    try:
        import toml

        def load_toml(path: Path) -> dict:
            """Load TOML file using toml package (Python < 3.11)."""
            return toml.load(path)

    except ImportError:
        print(
            "Error: No TOML parser available. Install 'toml' package for Python < 3.11",
            file=sys.stderr,
        )
        sys.exit(1)


def get_nested_value(data: dict, key: str):
    """
    Get a nested value from a dict using dot notation.

    Args:
        data: The dict to search
        key: Dot-separated key path (e.g., "agent.data_volume")

    Returns:
        The value if found, or None if not found
    """
    parts = key.split(".")
    current = data
    for part in parts:
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def key_exists(data: dict, key: str) -> bool:
    """
    Check if a nested key exists in a dict.

    Args:
        data: The dict to search
        key: Dot-separated key path

    Returns:
        True if key exists, False otherwise
    """
    parts = key.split(".")
    current = data
    for part in parts:
        if not isinstance(current, dict) or part not in current:
            return False
        current = current[part]
    return True


def format_value(value) -> str:
    """
    Format a value for shell-friendly output.

    - Strings are output as-is
    - Booleans are output as lowercase "true"/"false"
    - Numbers are output as strings
    - Complex types (lists, dicts) are output as JSON

    Args:
        value: The value to format

    Returns:
        String representation suitable for shell consumption
    """
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return value
    # For complex types (list, dict), output as JSON
    return json.dumps(value, separators=(",", ":"))


def main():
    parser = argparse.ArgumentParser(
        description="Parse ContainAI TOML config file for shell consumption"
    )
    parser.add_argument(
        "--file",
        "-f",
        required=True,
        help="Path to TOML config file",
    )
    parser.add_argument(
        "--key",
        "-k",
        help="Dot-separated key path to retrieve (e.g., agent.data_volume)",
    )
    parser.add_argument(
        "--json",
        "-j",
        action="store_true",
        dest="output_json",
        help="Output entire config as JSON",
    )
    parser.add_argument(
        "--exists",
        "-e",
        help="Check if key exists (exit 0 if exists, 1 if not)",
    )

    args = parser.parse_args()

    # Validate mutually exclusive options
    mode_count = sum([bool(args.key), args.output_json, bool(args.exists)])
    if mode_count == 0:
        print("Error: Must specify one of --key, --json, or --exists", file=sys.stderr)
        sys.exit(1)
    if mode_count > 1:
        print(
            "Error: Options --key, --json, and --exists are mutually exclusive",
            file=sys.stderr,
        )
        sys.exit(1)

    # Load the TOML file
    config_path = Path(args.file)
    try:
        config = load_toml(config_path)
    except FileNotFoundError:
        print(f"Error: File not found: {args.file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        # Handle TOML parse errors from either library
        print(f"Error: Invalid TOML: {e}", file=sys.stderr)
        sys.exit(1)

    # Handle --exists mode
    if args.exists:
        if key_exists(config, args.exists):
            sys.exit(0)
        else:
            sys.exit(1)

    # Handle --json mode
    if args.output_json:
        print(json.dumps(config, indent=2))
        sys.exit(0)

    # Handle --key mode
    if args.key:
        value = get_nested_value(config, args.key)
        # Missing key outputs empty string and exits 0 (per spec)
        if value is None:
            print("")
        else:
            print(format_value(value))
        sys.exit(0)


if __name__ == "__main__":
    main()
