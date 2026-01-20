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
- `env_file` with empty `import = []`: `env_file` still validated (error if missing/unreadable), but no vars imported

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
printf '%s\n' "$env_content" | docker --context "$ctx" run --rm -i \
  --network=none \
  -v "$volume:/data" \
  alpine sh -c '
    # Verify mount point not symlink
    [ ! -L /data ] || exit 1
    [ -d /data ] || exit 1
    # Create temp as root
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
- Volume inspect/create: `docker --context "$ctx" volume inspect/create`
- Rsync container: `docker --context "$ctx" run`
- Transform containers: `docker --context "$ctx` run`
- Orphan cleanup: `docker --context "$ctx" run`
- **New .env helper**: `docker --context "$ctx" run`

**3-Tier Context Selection Strategy:**
1. **Sysbox available**: Use `containai-secure` context (ECI/Sysbox mode)
2. **Docker Desktop detected** (`docker context ls | grep -q desktop-linux`): Use `desktop-linux` context
3. **Fallback**: Use `default` context with `[WARN] Using default context - volume may be on different daemon`

**Implementation approach:**
1. Add context selection to `_containai_import_cmd` (mirroring `lib/container.sh`'s `_cai_select_context`)
2. Create `docker_cmd` variable or pass `ctx` parameter to ALL docker invocations in `lib/import.sh`
3. Apply to existing rsync/transform/orphan commands (not just new .env helper)

**DOCKER_CONTEXT/DOCKER_HOST neutralization:**
- When explicit `--context` flag is used, env vars should NOT override it
- Before docker commands: `unset DOCKER_CONTEXT DOCKER_HOST` or use `env -u DOCKER_CONTEXT -u DOCKER_HOST docker --context ...`
- This ensures `--context` flag is authoritative

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
    # Skip comments
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    # Skip blank/whitespace-only lines (spaces and tabs)
    if [[ -z "${line//[[:space:]]/}" ]]; then continue; fi
    # Strip optional 'export ' prefix
    if [[ "$line" =~ ^export[[:space:]]+ ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace
    fi
    # Require = before parsing
    if [[ "$line" != *=* ]]; then
      log "WARN: line $line_num: no = found - skipping"
      continue
    fi
    # Extract key and value
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
- Entrypoint doesn't override pre-set env vars (including empty string)
- Permission handling (0600, owned by 1000:1000)
- CRLF stripping works
- `export KEY=VALUE` format accepted
- Lines without `=` skipped with warning
- Invalid key names skipped with warning

**Context testing approach:**
- Context selection is tested implicitly by verifying volume contents match expectations
- Explicit multi-context tests require ECI/Sysbox infrastructure (skip on non-ECI CI)
- Use `[[ -n "$(docker context ls | grep containai-secure)" ]]` to detect ECI availability
- Non-ECI tests verify default/desktop-linux selection logic without requiring multiple daemons

## Acceptance Criteria

1. [ ] Config `[env].import` specifies allowlist of env var names
2. [ ] Missing/invalid `[env].import` treated as `[]` with `[WARN]`
3. [ ] Var names validated against `^[A-Za-z_][A-Za-z0-9_]*$`, invalid skipped with warning
4. [ ] Config `[env].from_host` (default false) enables host env reading
5. [ ] Config `[env].env_file` specifies source .env file path (workspace-relative only)
6. [ ] `env_file` set but missing/unreadable: **hard error**
7. [ ] Only allowlisted vars are imported (no accidental leakage)
8. [ ] Missing vars logged as warning (key only, not value), not fatal
9. [ ] Output `.env` written atomically with TOCTOU protection
10. [ ] Output `.env` has mode 0600, owned by 1000:1000
11. [ ] Host env multiline values skipped with `[WARN] source=host: key 'FOO' skipped (multiline value)`
12. [ ] Entrypoint loads `.env` safely (no shell `source`)
13. [ ] Entrypoint only sets vars NOT already in environment (empty string = present)
14. [ ] Entrypoint strips CRLF, handles `export ` prefix, and is `set -e` safe
15. [ ] `cai import` triggers env var import via dedicated env config resolution
16. [ ] ALL docker commands use correct context (existing + new)
17. [ ] Values streamed via stdin, written as root, then chown/chmod
18. [ ] Dry-run prints what would be imported (keys only), no volume write
19. [ ] Log hygiene: never print values or raw lines in warnings
20. [ ] Missing Python: skip env import with warning (fail fast if --config explicit)

## References

- Existing import: `agent-sandbox/lib/import.sh`
- Context logic: `agent-sandbox/lib/container.sh`
- Config parsing: `agent-sandbox/lib/config.sh`, `agent-sandbox/parse-toml.py`
- Entrypoint: `agent-sandbox/entrypoint.sh`
- Volume mount: `/mnt/agent-data`
- OWASP guidance: env vars visible via docker inspect (not for high-sensitivity secrets)
