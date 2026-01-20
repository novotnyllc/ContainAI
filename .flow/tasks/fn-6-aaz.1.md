# fn-6-aaz.1 Extend TOML parser for [env] section

## Description
Extend `parse-toml.py` to support the `[env]` section for env var import configuration.

**Size:** S  
**Files:** `agent-sandbox/parse-toml.py`

## Approach

- Follow existing pattern at `parse-toml.py:89-140` for section parsing
- Add handler for `[env]` section with keys: `import` (list), `from_host` (bool), `env_file` (string)
- Return env config as JSON alongside existing volume/excludes output

## Key Context

- Existing parser uses `tomllib` (Python 3.11+) or `tomli` fallback
- Output format is JSON to stdout, consumed by bash
- Error handling: invalid types should print clear error message
## Acceptance
- [ ] `[env].import` parsed as list of strings
- [ ] `[env].from_host` parsed as boolean (default: false)
- [ ] `[env].env_file` parsed as optional string
- [ ] Invalid types produce clear error messages
- [ ] Missing `[env]` section returns empty/null (not error)
- [ ] JSON output includes env config
## Done summary
Extended parse-toml.py with --env mode to validate and extract [env] section for env var import configuration. Supports import (list), from_host (bool), and env_file (string) with proper type validation and fail-soft/fail-closed semantics per spec.
## Evidence
- Commits: cd6da7e, d635293
- Tests: python3 -m py_compile agent-sandbox/parse-toml.py, manual testing with various TOML configs
- PRs: