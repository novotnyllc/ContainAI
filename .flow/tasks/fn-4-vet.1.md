# fn-4-vet.1 Add TOML config parser helper script

## Description
## Overview
Create a Python helper script that parses TOML config files and resolves the volume name based on workspace path matching using **path-segment boundary matching** (longest match wins).

## Implementation

### File Location
`agent-sandbox/parse-toml.py`

### Python Version Handling
The script must handle Python version detection internally:
```python
#!/usr/bin/env python3
import sys

try:
    import tomllib  # Python 3.11+
except ImportError:
    try:
        import tomli as tomllib  # Fallback for Python < 3.11
    except ImportError:
        print("Error: Python 3.11+ or tomli package required", file=sys.stderr)
        sys.exit(1)
```

### Workspace Matching Algorithm (Path-Segment Boundary)

A section path P matches workspace W if:
- W equals P exactly, OR
- W starts with P AND the character after P in W is `/`

Example:
- `/a/b` matches `/a/b` ✓ (exact)
- `/a/b` matches `/a/b/c` ✓ (prefix with / boundary)
- `/a/b` does NOT match `/a/bc` ✗ (no segment boundary)

### Script Modes

**Mode 1: Simple key lookup**
```bash
python3 parse-toml.py <config-file> <key-path>
```

**Mode 2: Workspace path matching**
```bash
python3 parse-toml.py <config-file> --workspace <path> --config-dir <dir>
```

### Examples

```bash
# Longest segment-boundary match
# [workspace."/a/b"] and [workspace."/a/b/c"] both exist
python3 parse-toml.py config.toml --workspace /a/b/c/d --config-dir /
# Returns value from [workspace."/a/b/c"] (longer match)

# Segment boundary prevents false match
python3 parse-toml.py config.toml --workspace /a/bc --config-dir /
# Does NOT match [workspace."/a/b"], falls back to [agent]
```

## Key Files
- Create: `agent-sandbox/parse-toml.py`
## Overview
Create a Python helper script that parses TOML config files and resolves the volume name based on workspace path matching using **longest prefix match** (no glob patterns in v1).

## Implementation

### File Location
`agent-sandbox/parse-toml.py`

### Script Modes

**Mode 1: Simple key lookup**
```bash
python3 parse-toml.py <config-file> <key-path>
# Example: python3 parse-toml.py config.toml agent.data_volume
```

**Mode 2: Workspace path matching**
```bash
python3 parse-toml.py <config-file> --workspace <path> --config-dir <dir>
# Example: python3 parse-toml.py config.toml --workspace /home/user/myproject --config-dir /home/user
```

### Workspace Matching Algorithm (v1 - Prefix Match)

1. Get all `[workspace.<path>]` sections from config
2. For each section:
   - If path starts with `./` or `../`: resolve relative to `--config-dir`
   - Otherwise treat as absolute path
   - Normalize (remove trailing slashes)
3. Compare workspace path against all normalized section paths
4. **Longest matching prefix wins** (simple string prefix, not glob)
5. Return `data_volume` from matched section
6. Fall back to `[agent].data_volume` if no match
7. Return empty string if no fallback exists

### Examples

```bash
# Config file:
# [agent]
# data_volume = "default"
# [workspace."/home/user/project"]
# data_volume = "project-vol"
# [workspace."/home/user/project/subdir"]
# data_volume = "subdir-vol"

# Exact match
python3 parse-toml.py config.toml --workspace /home/user/project --config-dir /home/user
# Returns: project-vol

# Longest prefix match
python3 parse-toml.py config.toml --workspace /home/user/project/subdir --config-dir /home/user
# Returns: subdir-vol (longer match wins over /home/user/project)

# No match, fallback to [agent]
python3 parse-toml.py config.toml --workspace /other/path --config-dir /home/user
# Returns: default
```

### Error Handling
- File not found: stderr message, exit 1
- Invalid TOML syntax: stderr with file path and error, exit 1
- Missing key/no match: empty stdout, exit 0

## Key Files
- Create: `agent-sandbox/parse-toml.py`
## Overview
Create a Python helper script that parses TOML config files and resolves the volume name based on workspace path matching. This enables bash scripts to read TOML configuration with workspace-specific overrides.

## Implementation

### File Location
`agent-sandbox/parse-toml.py`

### Script Modes

**Mode 1: Simple key lookup**
```bash
python3 parse-toml.py <config-file> <key-path>
# Example: python3 parse-toml.py config.toml agent.data_volume
# Output: my-project-data
```

**Mode 2: Workspace path matching**
```bash
python3 parse-toml.py <config-file> --workspace <path> --config-dir <dir>
# Example: python3 parse-toml.py config.toml --workspace /home/user/myproject --config-dir /home/user
# Output: project-specific-volume (or fallback to agent.data_volume)
```

### Workspace Matching Logic

1. Get all `[workspace.<path>]` sections from config
2. For each section:
   - If path starts with `./` or `../`, resolve relative to `--config-dir`
   - Otherwise treat as absolute path
   - Support glob patterns (e.g., `*/tests`)
3. Match against provided `--workspace` path
4. **Longest match wins** when multiple patterns match
5. Return `data_volume` from matched section
6. Fall back to `[agent].data_volume` if no match
7. Return empty string if no fallback exists

### Interface Examples

```bash
# Simple key lookup
python3 parse-toml.py .containai/config.toml agent.data_volume
# Output: default-vol

# Workspace matching - exact match
python3 parse-toml.py config.toml --workspace /home/user/project --config-dir /home/user
# Matches [workspace."/home/user/project"] if exists

# Workspace matching - relative path
python3 parse-toml.py config.toml --workspace /repo/subdir --config-dir /repo
# Matches [workspace."./subdir"] resolved to /repo/subdir

# Workspace matching - glob
python3 parse-toml.py config.toml --workspace /home/user/project/tests --config-dir /home/user
# Matches [workspace."*/tests"] 

# No match - falls back to [agent]
python3 parse-toml.py config.toml --workspace /other/path --config-dir /home/user
# Returns [agent].data_volume value
```

### Error Handling
- File not found: stderr message, exit 1
- Invalid TOML syntax: stderr with file path and error, exit 1
- Missing key/no match: empty stdout, exit 0 (allows fallback to default)

## Key Files
- Create: `agent-sandbox/parse-toml.py`
## Overview
Create a minimal Python helper script that parses TOML config files and outputs the value of a specific key. This enables bash scripts to read TOML configuration. **Python is optional** - the bash wrapper must handle missing Python gracefully.

## Implementation

### File Location
`agent-sandbox/parse-toml.py`

### Script Requirements
1. Accept config file path and key path as arguments
2. Output the value to stdout (no newline if single value)
3. Exit 0 on success, non-zero on error
4. Support nested keys with dot notation: `agent.data_volume`, `profile.testing.data_volume`
5. Use `tomllib` (Python 3.11+) with fallback to `tomli`

### Interface
```bash
# Usage: parse-toml.py <config-file> <key-path>
python3 agent-sandbox/parse-toml.py .containai/config.toml agent.data_volume
# Output: my-project-data

# Missing key returns empty string, exit 0
python3 agent-sandbox/parse-toml.py .containai/config.toml missing.key
# Output: (empty)

# Invalid file returns error, exit 1
python3 agent-sandbox/parse-toml.py nonexistent.toml agent.data_volume
# stderr: Error: File not found: nonexistent.toml
```

### Error Handling
- File not found: stderr message, exit 1
- Invalid TOML syntax: stderr with file path and error, exit 1
- Missing key: empty stdout, exit 0 (allows fallback to default)
- Bash wrapper handles missing Python separately (not this script's concern)

## Key Files
- Create: `agent-sandbox/parse-toml.py`
- Reference: `agent-sandbox/entrypoint.sh` for error message patterns
## Overview
Create a minimal Python helper script that parses TOML config files and outputs the value of a specific key. This enables bash scripts to read TOML configuration without complex parsing logic.

## Implementation

### File Location
`agent-sandbox/parse-toml.py`

### Script Requirements
1. Accept config file path and key path as arguments
2. Output the value to stdout (no newline if single value)
3. Exit 0 on success, non-zero on error
4. Support nested keys with dot notation: `agent.volume`
5. Use `tomllib` (Python 3.11+) with fallback to `tomli`

### Interface
```bash
# Usage: parse-toml.py <config-file> <key-path>
python3 agent-sandbox/parse-toml.py .containai/config.toml agent.volume
# Output: my-project-data

# Missing key returns empty string, exit 0
python3 agent-sandbox/parse-toml.py .containai/config.toml missing.key
# Output: (empty)

# Invalid file returns error, exit 1
python3 agent-sandbox/parse-toml.py nonexistent.toml agent.volume
# stderr: Error: File not found: nonexistent.toml
```

### Error Handling
- File not found: stderr message, exit 1
- Invalid TOML syntax: stderr with file path and error, exit 1
- Missing key: empty stdout, exit 0 (allows fallback to default)
- Missing Python: bash wrapper should detect and error gracefully

## Key Files
- Create: `agent-sandbox/parse-toml.py`
- Reference: `agent-sandbox/entrypoint.sh` for error message patterns
## Acceptance
- [ ] Script handles Python version: tries tomllib, falls back to tomli
- [ ] Errors with clear message if neither tomllib nor tomli available
- [ ] Simple key lookup works
- [ ] Workspace matching with absolute paths works
- [ ] Workspace matching with relative paths works
- [ ] **Path-segment boundary matching**: /a/b matches /a/b/c but NOT /a/bc
- [ ] **Longest match wins** among valid matches
- [ ] Falls back to `[agent].data_volume` when no match
- [ ] Returns empty for no match (exit 0)
- [ ] Errors on invalid file/TOML (exit 1)
- [ ] Has shebang `#!/usr/bin/env python3`
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
