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

# Sentinel for "key not found" (distinct from None which is a valid TOML value)
_NOT_FOUND = object()

# Python 3.11+ has tomllib in stdlib
# Fallback chain: tomllib (3.11+) -> tomli (backport, installed via python3-tomli) -> toml (legacy)
_TOML_DECODE_ERROR = Exception  # Default, will be overwritten

try:
    import tomllib

    _TOML_DECODE_ERROR = tomllib.TOMLDecodeError

    def load_toml(path: Path) -> dict:
        """Load TOML file using tomllib (Python 3.11+)."""
        with open(path, "rb") as f:
            return tomllib.load(f)

except ImportError:
    try:
        # tomli is the backport of tomllib for Python < 3.11
        # Installed via python3-tomli on Debian/Ubuntu
        import tomli

        _TOML_DECODE_ERROR = tomli.TOMLDecodeError

        def load_toml(path: Path) -> dict:
            """Load TOML file using tomli (Python 3.8-3.10 backport)."""
            with open(path, "rb") as f:
                return tomli.load(f)

    except ImportError:
        try:
            # Legacy fallback to toml package
            import toml

            _TOML_DECODE_ERROR = toml.TomlDecodeError

            def load_toml(path: Path) -> dict:
                """Load TOML file using toml package (legacy fallback)."""
                return toml.load(path)

        except ImportError:
            print(
                "Error: No TOML parser available. Install 'tomli' or 'toml' package",
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
        The value if found, or _NOT_FOUND sentinel if not found
    """
    parts = key.split(".")
    current = data
    for part in parts:
        if not isinstance(current, dict) or part not in current:
            return _NOT_FOUND
        current = current[part]
    return current


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
    # For complex types (list, dict, datetime), output as compact JSON
    # Use default=str to handle TOML datetime types
    return json.dumps(value, separators=(",", ":"), default=str)


class ErrorExitParser(argparse.ArgumentParser):
    """ArgumentParser that exits with code 1 on errors (not 2)."""

    def error(self, message: str) -> None:
        """Print error message and exit with code 1."""
        self.print_usage(sys.stderr)
        print(f"{self.prog}: error: {message}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = ErrorExitParser(
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
        help="Output entire config as JSON (compact format)",
    )
    parser.add_argument(
        "--exists",
        "-e",
        help="Check if key exists (exit 0 if exists, 1 if not)",
    )

    args = parser.parse_args()

    # Validate mutually exclusive options
    # Use 'is not None' to correctly handle empty string keys
    mode_count = sum(
        [args.key is not None, args.output_json, args.exists is not None]
    )
    if mode_count == 0:
        print(
            "Error: Must specify one of --key, --json, or --exists", file=sys.stderr
        )
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
    except PermissionError:
        print(f"Error: Permission denied: {args.file}", file=sys.stderr)
        sys.exit(1)
    except IsADirectoryError:
        print(f"Error: Path is a directory: {args.file}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"Error: Cannot read file: {e}", file=sys.stderr)
        sys.exit(1)
    except _TOML_DECODE_ERROR as e:
        print(f"Error: Invalid TOML: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        # Catch-all for unexpected errors (bugs, edge cases in TOML libraries)
        print(f"Error: Failed to parse file: {e}", file=sys.stderr)
        sys.exit(1)

    # Handle --exists mode
    if args.exists is not None:
        value = get_nested_value(config, args.exists)
        if value is not _NOT_FOUND:
            sys.exit(0)
        else:
            sys.exit(1)

    # Handle --json mode (compact format for shell consumption)
    if args.output_json:
        try:
            print(json.dumps(config, separators=(",", ":"), default=str))
        except Exception as e:
            print(f"Error: Cannot serialize config: {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)

    # Handle --key mode
    if args.key is not None:
        value = get_nested_value(config, args.key)
        # Missing key outputs empty (no newline) and exits 0 (per spec)
        if value is _NOT_FOUND:
            sys.stdout.write("")
        else:
            print(format_value(value))
        sys.exit(0)


if __name__ == "__main__":
    main()
