# fn-5-urz.3 TOML config parser (parse-toml.py)

## Description
## Overview

Create a minimal Python TOML parser that shell scripts can call to read configuration values.

## File

`agent-sandbox/parse-toml.py`

## Interface

```bash
# Get a single value
python3 parse-toml.py --file config.toml --key agent.data_volume
# Output: sandbox-agent-data

# Get all values as JSON
python3 parse-toml.py --file config.toml --json
# Output: {"agent": {"data_volume": "..."}, ...}

# Check if key exists
python3 parse-toml.py --file config.toml --exists agent.data_volume
# Exit code: 0 if exists, 1 if not
```

## Config Schema

```toml
[agent]
data_volume = "sandbox-agent-data"

[credentials]
mode = "sandbox"  # sandbox | host | none

[danger]
allow_host_credentials = false
allow_host_docker_socket = false

[secure_engine]
enabled = "auto"  # true | false | auto
context_name = "containai-secure"
seccomp_profile = ""  # optional path
```

## Implementation

- Use Python 3.11+ `tomllib` (stdlib, no dependencies)
- Fallback to `toml` package for Python < 3.11
- Use `argparse` for CLI (per repo conventions)
- Exit 0 on success, 1 on error (with message to stderr)

## Reuse

- `flowctl.py` argparse patterns (`.flow/bin/flowctl.py`)
## Acceptance
- [ ] Reads TOML files with nested keys
- [ ] `--key` returns single value to stdout
- [ ] `--json` returns full config as JSON
- [ ] `--exists` returns exit code without output
- [ ] Works with Python 3.8+ (tomllib fallback for < 3.11)
- [ ] Handles missing file gracefully (error to stderr, exit 1)
- [ ] Handles missing key gracefully (empty output, exit 0 for --key)
## Done summary
Implemented parse-toml.py CLI with --file, --key, --json, --exists options. Uses tomllib (3.11+) with tomli fallback for Python 3.8+. Updated config.sh to use the new interface with stdin JSON passing for security.
## Evidence
- Commits: 3002600, b015788, c855bce
- Tests: python3 parse-toml.py --file config.toml --key/--json/--exists, bash source containai.sh + _containai_parse_config
- PRs: