#!/usr/bin/env python3
"""
parse-toml.py - Minimal TOML config parser for shell script consumption.

Provides a CLI interface for reading TOML configuration values, suitable
for calling from shell scripts that need to access config settings.

Usage:
    python3 parse-toml.py --file config.toml --key agent.data_volume
    python3 parse-toml.py --file config.toml --json
    python3 parse-toml.py --file config.toml --exists agent.data_volume
    python3 parse-toml.py --file config.toml --env
    python3 parse-toml.py --file config.toml --set-workspace-key /path key value
    python3 parse-toml.py --file config.toml --get-workspace /path
"""
import argparse
import json
import os
import re
import sys
import tempfile
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


def validate_env_section(config):
    """
    Validate and extract the [env] section from config.

    Validates types for:
    - import: list of strings (missing/invalid treated as empty list with warning)
    - from_host: boolean (default: false, invalid type is error)
    - env_file: optional string (invalid type is error)

    Per spec, env_file is always validated when [env] section exists, even if
    import is missing or invalid. This ensures "fail closed" semantics.

    Args:
        config: The parsed TOML config dict

    Returns:
        Validated env config dict, or None if [env] section is missing.
        Prints warnings to stderr for recoverable issues.

    Raises:
        SystemExit: If type validation fails for from_host or env_file
    """
    env_section = config.get("env")

    # Missing [env] section - return None (not error)
    if env_section is None:
        return None

    # [env] exists but is not a dict - error
    if not isinstance(env_section, dict):
        print("Error: [env] section must be a table/dict", file=sys.stderr)
        sys.exit(1)

    result = {}

    # Validate 'env_file' key FIRST - per spec, always validated when [env] exists
    # This ensures fail-closed semantics even if import is invalid
    env_file = env_section.get("env_file")
    if env_file is None:
        # Optional - don't include in result if not present
        pass
    elif not isinstance(env_file, str):
        print(
            f"Error: [env].env_file must be a string, got {type(env_file).__name__}",
            file=sys.stderr,
        )
        sys.exit(1)
    else:
        result["env_file"] = env_file

    # Validate 'from_host' key: must be boolean, default false
    # Invalid type is an error (not recoverable)
    from_host = env_section.get("from_host")
    if from_host is None:
        result["from_host"] = False
    elif not isinstance(from_host, bool):
        print(
            f"Error: [env].from_host must be a boolean, got {type(from_host).__name__}",
            file=sys.stderr,
        )
        sys.exit(1)
    else:
        result["from_host"] = from_host

    # Validate 'import' key: must be list of strings
    # Per spec: missing or non-list is treated as [] with warning (fail-soft)
    import_list = env_section.get("import")
    if import_list is None:
        # Missing import key - treat as empty list with warning
        print("[WARN] [env].import missing, treating as empty list", file=sys.stderr)
        result["import"] = []
    elif not isinstance(import_list, list):
        # Non-list - treat as empty list with warning (per spec)
        print(
            f"[WARN] [env].import must be a list, got {type(import_list).__name__}; treating as empty list",
            file=sys.stderr,
        )
        result["import"] = []
    else:
        # Validate each item is a string, skip non-strings with warning
        validated_imports = []
        for i, item in enumerate(import_list):
            if not isinstance(item, str):
                print(
                    f"[WARN] [env].import[{i}] must be a string, got {type(item).__name__}; skipping",
                    file=sys.stderr,
                )
                continue
            validated_imports.append(item)
        result["import"] = validated_imports

    return result


def get_workspace_state(config: dict, workspace_path: str) -> dict:
    """
    Get workspace state for a specific path from config.

    Args:
        config: The parsed TOML config dict
        workspace_path: The workspace path (must be absolute, normalized)

    Returns:
        Dict with workspace state keys (data_volume, container_name, agent, created_at)
        or empty dict if not found
    """
    workspaces = config.get("workspace", {})
    if not isinstance(workspaces, dict):
        return {}

    ws_state = workspaces.get(workspace_path, {})
    if not isinstance(ws_state, dict):
        return {}

    return ws_state


def format_toml_string(value: str) -> str:
    """
    Format a string value for TOML output.

    Uses basic strings with escaping. Literal strings are avoided because
    TOML literal strings cannot contain control characters (tab, CR, etc).
    """
    # Check if value contains characters that need escaping
    has_control = any(c in value for c in ["\n", "\r", "\t"])
    has_special = any(c in value for c in ['"', "\\"])

    if has_control or has_special:
        # Always use escaped basic string for control chars or special chars
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        escaped = escaped.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
        return f'"{escaped}"'
    return f'"{value}"'


def unset_workspace_key(file_path: Path, workspace_path: str, key: str) -> bool:
    """
    Unset (remove) a key from a workspace section atomically.

    If the workspace section becomes empty after removing the key,
    the entire section is removed.

    Args:
        file_path: Path to the TOML config file
        workspace_path: The workspace path (key for [workspace."path"] table)
        key: The key to unset

    Returns:
        True on success, False on failure (error printed to stderr)
    """
    # Validate key name
    if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", key):
        print(f"Error: Invalid key name: {key}", file=sys.stderr)
        return False

    # Validate workspace path
    if not workspace_path.startswith("/"):
        print(f"Error: Workspace path must be absolute: {workspace_path}", file=sys.stderr)
        return False

    # Read existing file content
    if not file_path.exists():
        # Nothing to unset if file doesn't exist
        return True

    try:
        content = file_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        print(f"Error: Cannot read file: {e}", file=sys.stderr)
        return False

    # Build the workspace table header
    escaped_path = workspace_path.replace("\\", "\\\\").replace('"', '\\"')
    ws_header = f'[workspace."{escaped_path}"]'

    lines = content.split("\n")
    new_lines = []
    in_target_workspace = False
    ws_start_idx = -1
    ws_end_idx = -1
    key_removed = False
    any_table_pattern = re.compile(r"^\[")

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Check if this is the target workspace header
        header_part = stripped
        if stripped.startswith("[") and stripped.endswith("]"):
            header_part = stripped
        elif stripped.startswith("[") and "#" in stripped:
            close_bracket = stripped.rfind("]")
            if close_bracket > 0:
                header_part = stripped[:close_bracket + 1]

        if header_part == ws_header:
            in_target_workspace = True
            ws_start_idx = len(new_lines)
            new_lines.append(line)
            i += 1
            continue

        # Check if we're entering a different section
        if in_target_workspace and any_table_pattern.match(stripped):
            ws_end_idx = len(new_lines)
            in_target_workspace = False

        # If we're in the target workspace, look for the key to remove
        if in_target_workspace:
            key_match = re.match(rf"^{re.escape(key)}\s*=", stripped)
            if key_match:
                # Skip this line (remove the key)
                key_removed = True
                i += 1
                continue

        new_lines.append(line)
        i += 1

    # If we were still in target workspace at EOF
    if in_target_workspace:
        ws_end_idx = len(new_lines)

    # Check if workspace section is now empty (only header and blank lines)
    if ws_start_idx >= 0 and ws_end_idx > ws_start_idx:
        has_content = False
        for idx in range(ws_start_idx + 1, ws_end_idx):
            if idx < len(new_lines):
                line_stripped = new_lines[idx].strip()
                # Skip blank lines and comments
                if line_stripped and not line_stripped.startswith("#"):
                    has_content = True
                    break

        if not has_content:
            # Remove the entire workspace section (header and following blank lines)
            # Remove lines from ws_start_idx to ws_end_idx - 1
            del new_lines[ws_start_idx:ws_end_idx]
            # Also remove any trailing blank lines before the next section
            while new_lines and new_lines[-1].strip() == "":
                new_lines.pop()

    # Build final content
    final_content = "\n".join(new_lines)
    if final_content and not final_content.endswith("\n"):
        final_content += "\n"

    # Write atomically
    try:
        dir_path = file_path.parent
        if not dir_path.exists():
            return True  # Nothing to write if dir doesn't exist

        fd, temp_path = tempfile.mkstemp(
            prefix=".config_", suffix=".tmp", dir=str(dir_path)
        )
        temp_path = Path(temp_path)

        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(final_content.encode("utf-8"))
                f.flush()
                os.fsync(f.fileno())
            temp_path.rename(file_path)
        except Exception as e:
            try:
                temp_path.unlink()
            except OSError:
                pass
            raise e

    except OSError as e:
        print(f"Error: Cannot write file: {e}", file=sys.stderr)
        return False

    return True


def format_toml_value(key: str, value: str) -> str:
    """
    Format a value for TOML output with proper typing based on key.

    Known keys with specific types:
    - ssh.port_range_start, ssh.port_range_end: integers
    - ssh.forward_agent, import.auto_prompt: booleans
    - Everything else: strings

    Args:
        key: The config key (used to determine type)
        value: The value as a string

    Returns:
        TOML-formatted value (with quotes for strings, raw for ints/bools)
    """
    # Keys that should be integers
    int_keys = {
        "port_range_start",
        "port_range_end",
        "ssh.port_range_start",
        "ssh.port_range_end",
    }

    # Keys that should be booleans
    bool_keys = {
        "forward_agent",
        "auto_prompt",
        "ssh.forward_agent",
        "import.auto_prompt",
    }

    # Get the last part of the key for matching nested keys
    key_name = key.split(".")[-1] if "." in key else key

    # Check for integer keys
    if key in int_keys or key_name in int_keys:
        # Validate it's actually an integer
        try:
            int(value)
            return value  # Return raw integer for TOML
        except ValueError:
            # Fall through to string formatting
            pass

    # Check for boolean keys
    if key in bool_keys or key_name in bool_keys:
        # Convert to TOML boolean
        if value.lower() in ("true", "1", "yes"):
            return "true"
        elif value.lower() in ("false", "0", "no"):
            return "false"
        # Fall through to string formatting if not a valid bool

    # Default: format as string
    return format_toml_string(value)


def set_global_key(file_path: Path, key: str, value: str) -> bool:
    """
    Set a global (top-level) key in config atomically.

    Supports dot notation for nested keys (e.g., agent.default).
    Values are typed appropriately based on the key name.

    Args:
        file_path: Path to the TOML config file
        key: The key to set (dot notation for nested)
        value: The value to set

    Returns:
        True on success, False on failure
    """
    # Validate key name (allow dots for nesting)
    if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_.]*$", key):
        print(f"Error: Invalid key name: {key}", file=sys.stderr)
        return False

    parts = key.split(".")
    if len(parts) > 2:
        print(f"Error: Key nesting too deep (max 2 levels): {key}", file=sys.stderr)
        return False

    # Read existing content
    content = ""
    if file_path.exists():
        try:
            content = file_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as e:
            print(f"Error: Cannot read file: {e}", file=sys.stderr)
            return False

    lines = content.split("\n")
    new_lines = []
    # Format value with proper TOML type based on key
    kv_line = f"{parts[-1]} = {format_toml_value(key, value)}"

    if len(parts) == 1:
        # Top-level key
        key_updated = False
        in_table = False

        for line in lines:
            stripped = line.strip()

            # Check if entering a table section
            if stripped.startswith("["):
                in_table = True
                if not key_updated:
                    # Insert the key before the first table
                    new_lines.append(kv_line)
                    key_updated = True
                new_lines.append(line)
                continue

            # Check if this line sets the key (only if not in a table)
            if not in_table:
                key_match = re.match(rf"^{re.escape(parts[0])}\s*=", stripped)
                if key_match:
                    new_lines.append(kv_line)
                    key_updated = True
                    continue

            new_lines.append(line)

        if not key_updated:
            # Add at end if no tables, or at start if only tables
            if in_table:
                # Insert before first table
                for i, line in enumerate(new_lines):
                    if line.strip().startswith("["):
                        new_lines.insert(i, kv_line)
                        key_updated = True
                        break
            else:
                new_lines.append(kv_line)
    else:
        # Nested key (e.g., agent.default -> [agent] section)
        section_name = parts[0]
        section_header = f"[{section_name}]"
        key_updated = False
        in_target_section = False
        found_section = False
        section_end_idx = -1

        i = 0
        while i < len(lines):
            line = lines[i]
            stripped = line.strip()

            # Check if this is the target section header
            if stripped == section_header or stripped.startswith(f"{section_header} #"):
                in_target_section = True
                found_section = True
                new_lines.append(line)
                i += 1
                continue

            # Check if entering a different section
            if in_target_section and stripped.startswith("["):
                if not key_updated:
                    new_lines.append(kv_line)
                    key_updated = True
                in_target_section = False

            # Check if this line sets the key
            if in_target_section:
                key_match = re.match(rf"^{re.escape(parts[-1])}\s*=", stripped)
                if key_match:
                    new_lines.append(kv_line)
                    key_updated = True
                    i += 1
                    continue

            new_lines.append(line)
            i += 1

        # If we were still in target section at EOF
        if in_target_section and not key_updated:
            new_lines.append(kv_line)
            key_updated = True

        # If section wasn't found, create it
        if not found_section:
            if content.strip():
                new_lines.append("")
            new_lines.append(section_header)
            new_lines.append(kv_line)

    # Build final content
    final_content = "\n".join(new_lines)
    if not final_content.endswith("\n"):
        final_content += "\n"

    # Write atomically
    try:
        dir_path = file_path.parent
        if not dir_path.exists():
            dir_path.mkdir(parents=True, mode=0o700)

        fd, temp_path = tempfile.mkstemp(
            prefix=".config_", suffix=".tmp", dir=str(dir_path)
        )
        temp_path = Path(temp_path)

        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(final_content.encode("utf-8"))
                f.flush()
                os.fsync(f.fileno())
            temp_path.rename(file_path)
        except Exception as e:
            try:
                temp_path.unlink()
            except OSError:
                pass
            raise e

    except OSError as e:
        print(f"Error: Cannot write file: {e}", file=sys.stderr)
        return False

    return True


def unset_global_key(file_path: Path, key: str) -> bool:
    """
    Unset (remove) a global key from config atomically.

    Supports dot notation for nested keys (e.g., agent.default).
    If a section becomes empty, it is removed.

    Args:
        file_path: Path to the TOML config file
        key: The key to unset

    Returns:
        True on success, False on failure
    """
    if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_.]*$", key):
        print(f"Error: Invalid key name: {key}", file=sys.stderr)
        return False

    if not file_path.exists():
        return True  # Nothing to unset

    parts = key.split(".")

    try:
        content = file_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        print(f"Error: Cannot read file: {e}", file=sys.stderr)
        return False

    lines = content.split("\n")
    new_lines = []

    if len(parts) == 1:
        # Top-level key
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("["):
                new_lines.append(line)
                continue
            key_match = re.match(rf"^{re.escape(parts[0])}\s*=", stripped)
            if key_match:
                continue  # Skip this line
            new_lines.append(line)
    else:
        # Nested key
        section_name = parts[0]
        section_header = f"[{section_name}]"
        in_target_section = False
        section_start_idx = -1

        i = 0
        while i < len(lines):
            line = lines[i]
            stripped = line.strip()

            if stripped == section_header or stripped.startswith(f"{section_header} #"):
                in_target_section = True
                section_start_idx = len(new_lines)
                new_lines.append(line)
                i += 1
                continue

            if in_target_section and stripped.startswith("["):
                in_target_section = False

            if in_target_section:
                key_match = re.match(rf"^{re.escape(parts[-1])}\s*=", stripped)
                if key_match:
                    i += 1
                    continue  # Skip this line

            new_lines.append(line)
            i += 1

        # Check if section is now empty
        if section_start_idx >= 0:
            has_content = False
            section_end = len(new_lines)
            for idx in range(section_start_idx + 1, section_end):
                stripped = new_lines[idx].strip()
                if stripped.startswith("["):
                    section_end = idx
                    break
                if stripped and not stripped.startswith("#"):
                    has_content = True
                    break

            if not has_content:
                # Remove the section header and blank lines
                del new_lines[section_start_idx:section_end]

    # Build final content
    final_content = "\n".join(new_lines)
    if final_content and not final_content.endswith("\n"):
        final_content += "\n"

    # Write atomically
    try:
        dir_path = file_path.parent

        fd, temp_path = tempfile.mkstemp(
            prefix=".config_", suffix=".tmp", dir=str(dir_path)
        )
        temp_path = Path(temp_path)

        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(final_content.encode("utf-8"))
                f.flush()
                os.fsync(f.fileno())
            temp_path.rename(file_path)
        except Exception as e:
            try:
                temp_path.unlink()
            except OSError:
                pass
            raise e

    except OSError as e:
        print(f"Error: Cannot write file: {e}", file=sys.stderr)
        return False

    return True


def set_workspace_key(file_path: Path, workspace_path: str, key: str, value: str) -> bool:
    """
    Set a key in a workspace section atomically.

    This function reads the existing file, updates the workspace section,
    and writes back atomically (temp file + rename). It preserves comments
    and other sections in the file.

    Args:
        file_path: Path to the TOML config file
        workspace_path: The workspace path (key for [workspace."path"] table)
        key: The key to set within the workspace section
        value: The value to set (string)

    Returns:
        True on success, False on failure (error printed to stderr)
    """
    # Validate key name (alphanumeric, underscore, no injection)
    if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", key):
        print(f"Error: Invalid key name: {key}", file=sys.stderr)
        return False

    # Validate workspace path (must be absolute, no control characters)
    if not workspace_path.startswith("/"):
        print(f"Error: Workspace path must be absolute: {workspace_path}", file=sys.stderr)
        return False
    if "\0" in workspace_path:
        print("Error: Workspace path contains null byte", file=sys.stderr)
        return False
    if "\n" in workspace_path or "\r" in workspace_path:
        print("Error: Workspace path contains newline", file=sys.stderr)
        return False

    # Read existing file content (or start fresh)
    content = ""
    if file_path.exists():
        try:
            content = file_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as e:
            print(f"Error: Cannot read file: {e}", file=sys.stderr)
            return False

    # Build the workspace table header
    # Use quoted key format for paths: [workspace."/path/to/dir"]
    # Escape backslashes and quotes in the path for valid TOML
    escaped_path = workspace_path.replace("\\", "\\\\").replace('"', '\\"')
    ws_header = f'[workspace."{escaped_path}"]'

    # Format the key-value line
    kv_line = f"{key} = {format_toml_string(value)}"

    # Find and update or insert the workspace section
    # We need to be careful about preserving structure
    lines = content.split("\n")
    new_lines = []
    in_target_workspace = False
    found_workspace_section = False
    key_updated = False
    # Track position of last content line in workspace for proper insertion
    last_content_pos_in_workspace = -1
    i = 0

    # Pattern to match any table header (new section starts)
    any_table_pattern = re.compile(r"^\[")

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Check if this is the target workspace header
        # Handle potential inline comments after header: [workspace."/path"] # comment
        # Be careful: don't split on # inside quotes (path might contain #)
        header_part = stripped
        if stripped.startswith("[") and stripped.endswith("]"):
            # Simple case: no inline comment
            header_part = stripped
        elif stripped.startswith("[") and "#" in stripped:
            # Find the closing ] that ends the header, then check for # after
            close_bracket = stripped.rfind("]")
            if close_bracket > 0:
                after_bracket = stripped[close_bracket + 1:].lstrip()
                if after_bracket.startswith("#"):
                    # There's a comment after the header
                    header_part = stripped[:close_bracket + 1]
        if header_part == ws_header:
            in_target_workspace = True
            found_workspace_section = True
            new_lines.append(line)
            last_content_pos_in_workspace = len(new_lines) - 1
            i += 1
            continue

        # Check if we're entering a different section (ends current workspace)
        # Only match actual table headers [xxx], not array of tables [[xxx]]
        if in_target_workspace and any_table_pattern.match(stripped):
            # Before leaving the section, add the key if not yet updated
            if not key_updated:
                # Insert after last content line in workspace
                insert_pos = last_content_pos_in_workspace + 1
                new_lines.insert(insert_pos, kv_line)
                key_updated = True
            in_target_workspace = False

        # If we're in the target workspace section, look for the key
        if in_target_workspace:
            # Check if this line sets the target key
            key_match = re.match(rf"^{re.escape(key)}\s*=", stripped)
            if key_match:
                # Preserve any inline comment from the original line
                # TOML inline comments start with # outside of strings
                # Simple approach: check for # after the value portion
                inline_comment = ""
                # Find if there's a comment after the value (outside quotes)
                # This is a simplified check - full TOML parsing would be complex
                hash_pos = line.rfind("#")
                if hash_pos > 0:
                    # Check if # is outside quoted values (simple heuristic)
                    before_hash = line[:hash_pos]
                    # Count unescaped quotes - if even, # is outside strings
                    quote_count = before_hash.count('"') - before_hash.count('\\"')
                    if quote_count % 2 == 0:
                        inline_comment = " " + line[hash_pos:].rstrip()
                # Replace the line, preserving inline comment
                new_lines.append(kv_line + inline_comment)
                key_updated = True
                # Update last content position
                last_content_pos_in_workspace = len(new_lines) - 1
                i += 1
                continue
            # Track non-blank lines as content
            if stripped:
                new_lines.append(line)
                last_content_pos_in_workspace = len(new_lines) - 1
            else:
                new_lines.append(line)
            i += 1
            continue

        new_lines.append(line)
        i += 1

    # If we were still in target workspace at EOF, add the key
    if in_target_workspace and not key_updated:
        # Insert after last content line
        insert_pos = last_content_pos_in_workspace + 1
        new_lines.insert(insert_pos, kv_line)
        key_updated = True

    # If workspace section wasn't found, create it
    if not found_workspace_section:
        # Add blank line before new section if file isn't empty
        if content.strip():
            new_lines.append("")
        new_lines.append(ws_header)
        new_lines.append(kv_line)
        key_updated = True

    # Build final content
    final_content = "\n".join(new_lines)
    # Ensure file ends with newline
    if not final_content.endswith("\n"):
        final_content += "\n"

    # Write atomically: temp file in same directory, then rename
    # Using same directory ensures rename is atomic (same filesystem)
    try:
        dir_path = file_path.parent
        # Create parent directories if needed with secure permissions
        if not dir_path.exists():
            dir_path.mkdir(parents=True, mode=0o700)
        elif dir_path.is_file():
            print(f"Error: Config directory is a file: {dir_path}", file=sys.stderr)
            return False

        # Create temp file in same directory for atomic rename
        fd, temp_path = tempfile.mkstemp(
            prefix=".config_", suffix=".tmp", dir=str(dir_path)
        )
        temp_path = Path(temp_path)

        try:
            # Write content with secure permissions using proper file object
            # This ensures all bytes are written (os.write may be partial)
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(final_content.encode("utf-8"))
                f.flush()
                os.fsync(f.fileno())
            # fd is now closed by the context manager

            # Atomic rename
            temp_path.rename(file_path)
        except Exception as e:
            # Clean up temp file on failure
            try:
                temp_path.unlink()
            except OSError:
                pass
            raise e

    except OSError as e:
        print(f"Error: Cannot write file: {e}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Error: Unexpected error writing file: {e}", file=sys.stderr)
        return False

    return True


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
    parser.add_argument(
        "--env",
        action="store_true",
        help="Extract and validate [env] section (output as JSON, null if missing)",
    )
    parser.add_argument(
        "--set-workspace-key",
        nargs=3,
        metavar=("PATH", "KEY", "VALUE"),
        help="Set a key in workspace section: --set-workspace-key /path key value",
    )
    parser.add_argument(
        "--get-workspace",
        metavar="PATH",
        help="Get workspace state for path (output as JSON)",
    )
    parser.add_argument(
        "--unset-workspace-key",
        nargs=2,
        metavar=("PATH", "KEY"),
        help="Unset a key in workspace section: --unset-workspace-key /path key",
    )
    parser.add_argument(
        "--set-key",
        nargs=2,
        metavar=("KEY", "VALUE"),
        help="Set a global key: --set-key key value",
    )
    parser.add_argument(
        "--unset-key",
        metavar="KEY",
        help="Unset a global key: --unset-key key",
    )

    args = parser.parse_args()

    # Validate mutually exclusive options (all modes including write)
    # Use 'is not None' to correctly handle empty string keys
    mode_count = sum(
        [
            args.key is not None,
            args.output_json,
            args.exists is not None,
            args.env,
            args.get_workspace is not None,
            args.set_workspace_key is not None,
            args.unset_workspace_key is not None,
            args.set_key is not None,
            args.unset_key is not None,
        ]
    )
    if mode_count == 0:
        print(
            "Error: Must specify one of --key, --json, --exists, --env, --get-workspace, --set-workspace-key, --unset-workspace-key, --set-key, or --unset-key",
            file=sys.stderr,
        )
        sys.exit(1)
    if mode_count > 1:
        print(
            "Error: Options are mutually exclusive",
            file=sys.stderr,
        )
        sys.exit(1)

    # Handle --set-workspace-key mode (does not require loading file)
    if args.set_workspace_key:
        ws_path, ws_key, ws_value = args.set_workspace_key
        config_path = Path(args.file)
        if set_workspace_key(config_path, ws_path, ws_key, ws_value):
            sys.exit(0)
        else:
            sys.exit(1)

    # Handle --unset-workspace-key mode (does not require loading file)
    if args.unset_workspace_key:
        ws_path, ws_key = args.unset_workspace_key
        config_path = Path(args.file)
        if unset_workspace_key(config_path, ws_path, ws_key):
            sys.exit(0)
        else:
            sys.exit(1)

    # Handle --set-key mode (does not require loading file)
    if args.set_key:
        g_key, g_value = args.set_key
        config_path = Path(args.file)
        if set_global_key(config_path, g_key, g_value):
            sys.exit(0)
        else:
            sys.exit(1)

    # Handle --unset-key mode (does not require loading file)
    if args.unset_key:
        config_path = Path(args.file)
        if unset_global_key(config_path, args.unset_key):
            sys.exit(0)
        else:
            sys.exit(1)

    # Load the TOML file for read operations
    config_path = Path(args.file)
    try:
        config = load_toml(config_path)
    except FileNotFoundError:
        # For --get-workspace, missing file means empty workspace state
        if args.get_workspace is not None:
            print("{}")
            sys.exit(0)
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

    # Handle --get-workspace mode
    if args.get_workspace is not None:
        ws_state = get_workspace_state(config, args.get_workspace)
        try:
            print(json.dumps(ws_state, separators=(",", ":")))
        except Exception as e:
            print(f"Error: Cannot serialize workspace state: {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)

    # Handle --exists mode
    if args.exists is not None:
        value = get_nested_value(config, args.exists)
        if value is not _NOT_FOUND:
            sys.exit(0)
        else:
            sys.exit(1)

    # Handle --env mode (extract and validate [env] section)
    if args.env:
        env_config = validate_env_section(config)
        # Output as JSON: validated dict or null if section missing
        try:
            print(json.dumps(env_config, separators=(",", ":")))
        except Exception as e:
            print(f"Error: Cannot serialize env config: {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)

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
