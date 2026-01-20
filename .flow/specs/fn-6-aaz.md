# Allowlist-based Env Var Import

## Overview

Extend `cai import` to support allowlist-based environment variable import. Users specify which env vars to import via config, optionally reading from host environment (opt-in) and/or a source `.env` file. The result is a combined `.env` file written to the data volume.

**Key principle**: No accidental env var leakage. Explicit allowlist required, host env reading is opt-in (default: disabled).

## Scope

**In scope:**
- Config schema for env var allowlist (`[env]` section)
- Reading from host environment (opt-in)
- Reading from source `.env` file
- Writing combined `.env` to data volume
- Safe entrypoint loading of `.env` (no shell `source`)
- Integration with `cai import`
- Context-aware volume operations for ALL docker commands
- Dedicated env config resolution (independent of volume/excludes)

**Out of scope:**
- Pattern matching in allowlist (`APP_*` - literals only)
- `--env-file` flag for docker commands
- Secrets management (just env vars)
- Workspace-specific env config (`[workspace.*].env` ignored if present)

## Config Schema

```toml
[env]
# Allowlist of env var names to import
# Names must match ^[A-Za-z_][A-Za-z0-9_]*$ (POSIX)
# Invalid names logged as warning and skipped
# Duplicates deduplicated preserving first occurrence
# Missing or non-list: treated as [] with [WARN]
import = ["ANTHROPIC_API_KEY", "CONTEXT7_API_KEY", "DEBUG"]

# Optional: Read values from host environment
# Default: false (must opt-in explicitly)
from_host = true

# Optional: Read values from .env file
# Path is workspace-relative; absolute paths rejected with error
# File must exist and be readable (hard error if set but missing/unreadable)
env_file = ".env.sandbox"
```

**Config behavior:**
- Missing `[env]` section: skip env import silently (no log message)
- `[env]` exists but `import` missing/invalid: treat as `[]` with `[WARN]`, skip import
- Empty `import = []`: skip env import with `[INFO]`
- Duplicate keys in allowlist: deduplicate preserving order
- `[workspace.*].env`: IGNORED (workspace-specific env out of scope)
- `env_file` absolute path: rejected with error
- `env_file` outside workspace: rejected with error (resolved relative to workspace root)
- `env_file` set but missing/unreadable: **hard error** (not silent)
- **`env_file` validation when import is invalid/missing**: If `[env]` section exists and `env_file` is set, `env_file` is ALWAYS validated (even when `import` is missing/invalid and treated as `[]`). This ensures "fail closed" semantics.

**Dedicated env config resolution:**
- Env config is resolved INDEPENDENTLY of volume/excludes resolution
- Even if `--data-volume` or `--no-excludes` is used, config is still parsed for `[env]`
- New function `_containai_resolve_env_config()` reads config specifically for env settings

**Python availability:**
- If Python/config parsing unavailable: env import skipped with `[WARN]`
- If `--config` explicitly provided but Python unavailable: fail fast (matches existing strict behavior)

## Precedence (highest wins)

1. Runtime `-e` flags (already in container environment - NOT overwritten)
2. Host environment (if `from_host = true`)
3. Source `.env` file (if `env_file` specified)

**Empty string handling**: Empty string (`KEY=""`) is a valid value with full precedence:
- Host `KEY=""` overrides file `KEY=value`
- Runtime `-e KEY=` overrides both (entrypoint won't overwrite)
- "Present" means "set in environment" - empty string counts as present

**Entrypoint rule**: Only set `KEY` from `/mnt/agent-data/.env` if `KEY` is NOT already present in the container environment. Check with `[[ -z "${!key+x}" ]]` (unset vs empty).

## Input .env Parser Rules

Explicit parser for source `.env` file:
- Accept `KEY=VALUE` lines (optionally prefixed with `export `)
- Ignore full-line `#` comments and blank lines (including whitespace-only lines)
- Split on FIRST `=` only - remainder is value (spaces preserved)
- Validate KEY against `^[A-Za-z_][A-Za-z0-9_]*$`
- Skip lines without `=` with `[WARN]` message
- **Strip CRLF** (`\r`) from line endings
- No quote stripping (literal values only)

**Whitespace handling (explicit):**
- Leading whitespace before `export` or key: NOT trimmed, treated as invalid key (intentional strictness)
- Whitespace around `=`: NOT trimmed (e.g., `KEY = value` results in key `KEY ` which fails validation)
- This strict approach avoids ambiguous edge cases; users must use standard `.env` format

**Multiline value handling:**
- File parser reads line-by-line, so multiline values aren't naturally parsed
- If a line has no `=` and doesn't look like a key, it's likely a continuation - skip with `[WARN] line N: no = found`
- Host-derived values with embedded newline: `[WARN] source=host: key 'FOO' skipped (multiline value)`
- Detection for host values: `[[ "$value" == *$'\n'* ]]`
- Both formats omit the actual value for log hygiene

**Log hygiene (CRITICAL)**: Never print values or raw source lines in warnings/errors. Warn with `line_number` (for file) or `source=host` + `key` + reason only. This prevents accidental secret leakage to terminal logs.

## Output

- **Path**: `/mnt/agent-data/.env`
- **Format**: `KEY=VALUE` per line, no quotes, literal values
- **Permissions**: `0600` (owner read/write only), owned by `1000:1000`
- **Encoding**: UTF-8

**Volume permission handling:**
Docker volume roots are typically `root:root 0755`. User 1000 cannot write directly.

**Solution**: Write as root in helper container, then chown/chmod:
```bash
printf '%s\n' "$env_content" | DOCKER_CONTEXT= DOCKER_HOST= docker ${ctx:+--context "$ctx"} run --rm -i \
  --network=none \
  -v "$volume:/data" \
  alpine sh -c '
    # Verify mount point not symlink
    [ ! -L /data ] || exit 1
    [ -d /data ] || exit 1
    # Create temp as root (busybox mktemp accepts no template)
    tmp=$(mktemp -p /data)
    [ ! -L "$tmp" ] || { rm -f "$tmp"; exit 1; }
    cat > "$tmp"
    # Set ownership and permissions
    chown 1000:1000 "$tmp"
    chmod 600 "$tmp"
    # Verify target not symlink before rename
    [ ! -L /data/.env ] || { rm -f "$tmp"; exit 1; }
    mv "$tmp" /data/.env
  '
```

## Context-Aware Operations (CRITICAL)

**ALL docker commands in `cai import` must use the selected context.** This includes existing commands AND the new .env helper:
- Volume inspect/create: `docker ${ctx:+--context "$ctx"} volume inspect/create`
- Rsync container: `docker ${ctx:+--context "$ctx"} run`
- Transform containers: `docker ${ctx:+--context "$ctx"} run`
- Orphan cleanup: `docker ${ctx:+--context "$ctx"} run`
- **New .env helper**: `docker ${ctx:+--context "$ctx"} run`

**Context Selection (mirrors `cai run` in lib/container.sh exactly):**

`cai import` MUST use the **identical** context selection sequence as `cai run`. Since `cai import` is called from `containai.sh` (which already sources all required libs), context selection happens there:

**Implementation location**: Context selection stays in `containai.sh` (not lib/import.sh), matching how `cai run` works. The `_containai_import_cmd` function in `containai.sh` already has access to all required functions via existing sourcing.

```bash
# In _containai_import_cmd (containai.sh):

# Step 1: Resolve config override (same as lib/container.sh line ~1105)
local config_context_override=""
if config_context_override=$(_containai_resolve_secure_engine_context "$workspace" "$explicit_config"); then
    : # success
else
    # Parse error in strict mode - propagate failure
    return 1
fi

# Step 2: Select context using temporary env assignment (not env -u, which only works with external commands)
# Note: env -u only works with external commands, not shell functions!
# Use VAR= prefix for temporary override when calling shell functions
local selected_context=""
if selected_context=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_select_context "$config_context_override" "$debug_mode"); then
    : # success - selected_context is "" (ECI) or "containai-secure" (Sysbox)
else
    # No isolation available - fallback to default context with warning
    echo "[WARN] No isolation available, using default Docker context" >&2
    selected_context=""
fi

# Step 3: Pass selected_context to all docker calls via temporary env assignment
# Use DOCKER_CONTEXT= DOCKER_HOST= prefix for each docker command
```

**Resulting context values:**
- `""` (empty string) = Docker Desktop with ECI → NO `--context` flag (uses default)
- `"containai-secure"` = Sysbox mode → use `--context containai-secure`
- Selection failure (return 1) → fallback to `""` (default context) with `[WARN]`

**Implementation approach:**
1. Context selection happens in `containai.sh`'s `_containai_import_cmd` (NOT in lib/import.sh)
2. All required functions already available via existing sourcing in containai.sh
3. Use `DOCKER_CONTEXT= DOCKER_HOST=` prefix for context selection function call
4. Store result in `selected_context` local variable
5. Pass context to ALL docker invocations: `DOCKER_CONTEXT= DOCKER_HOST= docker ${selected_context:+--context "$selected_context"}`
6. For dry-run: print selected context in output for debuggability

**DOCKER_CONTEXT/DOCKER_HOST neutralization:**
- Use `DOCKER_CONTEXT= DOCKER_HOST=` prefix (temporary env assignment) for shell function calls
- Use `DOCKER_CONTEXT= DOCKER_HOST=` prefix for all docker commands (external commands)
- This approach:
  - Works correctly for both shell functions and external commands
  - Does NOT mutate user's shell environment (since it's a temporary prefix, not `unset`)
  - Is the same pattern used in `_cai_select_context` internally for its ECI check

**Failure mode**: If context mismatch occurs, `.env` lands in wrong daemon's volume - completely broken. This is a correctness requirement, not just nice-to-have.

## Entrypoint Loading Semantics

**Load timing**: After ownership fix (chown) completes. The volume may be unreadable until ownership is fixed.

**Error handling (with `set -euo pipefail` safety):**
- Unreadable `.env`: `[WARN]` and continue (do not abort) - use `if [[ -r ... ]]` guard
- Malformed lines: `[WARN]` per line (line number + key, no value), continue with valid lines
- Missing `.env`: silent (expected for first run) - use `if [[ -f ... ]]` guard

**"Present" definition**: A var is "present" if it's set in the environment, even if empty. `KEY=""` counts as present - do not override.

**Symlink protection**: Reject symlink before reading (mirror entrypoint's existing anti-symlink helpers).

**Safe parsing (no eval/source) with CRLF handling and `set -e` safety:**
```bash
_load_env_file() {
  local env_file="/mnt/agent-data/.env"

  # Guard against set -e - use if/else, not raw test
  if [[ ! -f "$env_file" ]]; then
    return 0  # Silent - expected for first run
  fi
  if [[ -L "$env_file" ]]; then
    log "WARN: .env is symlink - skipping"
    return 0
  fi
  if [[ ! -r "$env_file" ]]; then
    log "WARN: .env unreadable - skipping"
    return 0
  fi

  log "INFO: Loading environment from .env"
  local line_num=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # set -e safe increment (NOT ((line_num++)) which fails on 0)
    line_num=$((line_num + 1))
    # Strip CRLF
    line="${line%$'\r'}"
    # Skip comments (allows leading whitespace before #)
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    # Skip blank/whitespace-only lines (spaces and tabs)
    if [[ -z "${line//[[:space:]]/}" ]]; then continue; fi
    # Strip optional 'export ' prefix (must be at line start, no leading whitespace)
    if [[ "$line" =~ ^export[[:space:]]+ ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace after export
    fi
    # Require = before parsing
    if [[ "$line" != *=* ]]; then
      log "WARN: line $line_num: no = found - skipping"
      continue
    fi
    # Extract key and value (no whitespace trimming - strict format)
    local key="${line%%=*}"
    local value="${line#*=}"
    # Validate key
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      log "WARN: line $line_num: invalid key format - skipping"
      continue
    fi
    # Only set if not present (empty string = present)
    if [[ -z "${!key+x}" ]]; then
      export "$key=$value" || { log "WARN: line $line_num: export failed"; continue; }
    fi
  done < "$env_file"
}
```

## Dry-Run Behavior

When `cai import --dry-run` is used:
- Print what env vars would be imported/skipped (keys only, not values)
- Print selected context (for debuggability): `[INFO] Docker context: <ctx or "default">`
- Do NOT write `/mnt/agent-data/.env`
- Do NOT create/modify the volume
- Consistent with existing dry-run behavior in `test-sync-integration.sh`

## User Flow

```bash
# 1. User creates config
cat > .containai/config.toml <<'CONFIG'
[env]
import = ["ANTHROPIC_API_KEY", "CONTEXT7_API_KEY"]
from_host = true
CONFIG

# 2. User runs import
cai import

# Output:
# [INFO] Importing env vars to volume: containai-data
# [OK] Imported 2 env vars: ANTHROPIC_API_KEY, CONTEXT7_API_KEY
# [WARN] Skipped 0 vars (not found in host or file)

# 3. Container starts, entrypoint loads .env safely
cai run
```

## Quick Commands

```bash
# Smoke test: import with config
cat > /tmp/test-config.toml <<'TOML'
[env]
import = ["TEST_VAR"]
from_host = true
TOML
TEST_VAR=hello cai import --config /tmp/test-config.toml

# Verify .env was created in volume
docker run --rm -v containai-data:/data alpine cat /data/.env
# Expected: TEST_VAR=hello
```

## Test Requirements

Extend `agent-sandbox/test-sync-integration.sh` to cover:
- Dry-run doesn't create `/data/.env`
- Non-dry-run writes expected keys
- Values never appear in logs (log hygiene)
- Permission handling (0600, owned by 1000:1000)
- CRLF stripping works
- `export KEY=VALUE` format accepted
- Lines without `=` skipped with warning
- Invalid key names skipped with warning
- Whitespace edge cases (leading whitespace = invalid)

**Entrypoint testing strategy:**
The current integration tests bypass the entrypoint (`--entrypoint /bin/bash`) because `entrypoint.sh` requires Docker Sandbox's mirrored workspace mount (`findmnt` discovery).

**Solution - Two-tier testing:**
1. **Unit-style test for `_load_env_file`**: Extract the function to a separate testable file or add a `--test-env-load` mode that only runs the env loading portion. Test in a minimal container without workspace discovery.
2. **Full entrypoint test (ECI/Sandbox only)**: Add tests that run under Docker Sandbox infrastructure where `findmnt` discovery works. Gate with: `if _cai_sandbox_feature_enabled; then ... fi`

**Concrete approach for tier 1:**
```bash
# Create test container with .env pre-populated, verify env loading
docker run --rm \
  -v test-volume:/mnt/agent-data \
  -e PRE_SET_VAR=original \
  alpine sh -c '
    # Simulate entrypoint env loading (inline the function)
    env_file="/mnt/agent-data/.env"
    # ... (simplified _load_env_file logic)
    # Verify PRE_SET_VAR not overwritten
    [ "$PRE_SET_VAR" = "original" ] || exit 1
    # Verify NEW_VAR was set
    [ "$NEW_VAR" = "from_file" ] || exit 1
  '
```

**Context testing approach:**
- Tests must use the SAME context selection as `cai import`
- Before any docker volume/run operations in tests, call `_cai_select_context` and use result
- For dry-run tests: verify printed context matches expected selection
- Multi-daemon tests (ECI + Sysbox) skipped on non-ECI CI

## Acceptance Criteria

1. [ ] Config `[env].import` specifies allowlist of env var names
2. [ ] Missing/invalid `[env].import` treated as `[]` with `[WARN]`
3. [ ] Var names validated against `^[A-Za-z_][A-Za-z0-9_]*$`, invalid skipped with warning
4. [ ] Config `[env].from_host` (default false) enables host env reading
5. [ ] Config `[env].env_file` specifies source .env file path (workspace-relative only)
6. [ ] `env_file` set but missing/unreadable: **hard error**
7. [ ] `env_file` ALWAYS validated when `[env]` section exists (even if import is empty/invalid)
8. [ ] Only allowlisted vars are imported (no accidental leakage)
9. [ ] Missing vars logged as warning (key only, not value), not fatal
10. [ ] Output `.env` written atomically with TOCTOU protection
11. [ ] Output `.env` has mode 0600, owned by 1000:1000
12. [ ] Host env multiline values skipped with `[WARN] source=host: key 'FOO' skipped (multiline value)`
13. [ ] Entrypoint loads `.env` safely (no shell `source`)
14. [ ] Entrypoint only sets vars NOT already in environment (empty string = present)
15. [ ] Entrypoint strips CRLF, handles `export ` prefix, and is `set -e` safe
16. [ ] `cai import` uses identical context selection as `cai run` (resolve_secure_engine_context + select_context)
17. [ ] Context selection happens in containai.sh (not lib/import.sh) to use existing sourcing
18. [ ] ALL docker commands use `DOCKER_CONTEXT= DOCKER_HOST=` prefix (temporary env assignment)
19. [ ] Context selection failure falls back to default context (`""`) with `[WARN]`
20. [ ] Values streamed via stdin, written as root, then chown/chmod
21. [ ] Dry-run prints what would be imported (keys only) AND selected context
22. [ ] Log hygiene: never print values or raw lines in warnings
23. [ ] Missing Python: skip env import with warning (fail fast if --config explicit)
24. [ ] Whitespace handling is strict (no trimming, intentional)
25. [ ] Tests use same context selection as import (not hardcoded default)
26. [ ] Entrypoint tests have concrete strategy (unit-style + ECI-gated full test)

## References

- Existing import: `agent-sandbox/lib/import.sh`
- Context selection: `agent-sandbox/lib/doctor.sh` (`_cai_select_context`)
- Secure engine context: `agent-sandbox/lib/config.sh` (`_containai_resolve_secure_engine_context`)
- Context logic: `agent-sandbox/lib/container.sh` (reference implementation at lines ~1100-1115)
- Main entry: `agent-sandbox/containai.sh` (sources all libs, implements commands)
- Config parsing: `agent-sandbox/lib/config.sh`, `agent-sandbox/parse-toml.py`
- Entrypoint: `agent-sandbox/entrypoint.sh`
- Volume mount: `/mnt/agent-data`
- OWASP guidance: env vars visible via docker inspect (not for high-sensitivity secrets)
