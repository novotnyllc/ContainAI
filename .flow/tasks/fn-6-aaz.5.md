# fn-6-aaz.5 Update entrypoint to source .env

## Description
Update container entrypoint to safely load `.env` file with CRLF handling and `set -e` safety.

**Size:** S
**Files:** `agent-sandbox/entrypoint.sh`

## Approach

- **Load timing**: After ownership fix (chown) completes
- Implement safe line parser with CRLF stripping (`${line%$'\r'}`)
- **set -e safety**: Use explicit `if [[ -f/-r/-L ]]` guards (not raw reads)
- Error handling: unreadable/malformed warns and continues
- Malformed line warnings include line number + key (no value)
- Mirror existing anti-symlink helpers
## Approach

- **Load timing**: After ownership fix (chown) completes - volume may be unreadable until then
- Implement safe line parser (no `source`, no `eval`)
- Read `/mnt/agent-data/.env` line by line
- For each `KEY=VALUE` line:
  - Validate KEY format
  - **Only export if KEY not already in environment** (`-z "${!key+x}"` check)
  - "Present" means set even if empty - `KEY=""` counts as present
  - Use safe assignment without eval
- **Error handling**:
  - Unreadable .env: `[WARN]` and continue (do not abort)
  - Malformed lines: `[WARN]` per line, continue with valid lines
  - Missing .env: silent (expected for first run)
- Reject symlinks (mirror existing anti-symlink helpers)
## Approach

- Implement safe line parser (no `source`, no `eval`)
- Read `/mnt/agent-data/.env` line by line
- For each `KEY=VALUE` line:
  - Validate KEY format
  - **Only export if KEY not already in environment** (preserves `-e` flag precedence)
  - Use `export "$line"` for safe assignment
- Ignore `#` comments and blank lines
- Reject symlinks (security)
- Follow pattern at `entrypoint.sh:122-208` for file validation
## Approach

- Add sourcing near start of entrypoint, after volume structure setup
- Use `set -a` to auto-export, then `source`, then `set +a`
- Only source if file exists and is regular file (not symlink)
- Follow pattern at `entrypoint.sh:122-208` for file validation
## Acceptance
- [ ] Entrypoint loads `/mnt/agent-data/.env` if present
- [ ] **Load timing**: After ownership fix (chown) completes
- [ ] **CRLF stripping**: `${line%$'\r'}` applied
- [ ] **set -e safety**: Uses `if [[ -f ]]`, `if [[ -r ]]`, `if [[ -L ]]` guards
- [ ] **NO shell `source`** - uses safe line-by-line parser
- [ ] Only exports KEY if NOT already in environment
- [ ] "Present" = set even if empty (`KEY=""` not overwritten)
- [ ] Validates KEY format before export
- [ ] Unreadable .env: warns and continues (no abort)
- [ ] Malformed lines: warns with line number + key (no value)
- [ ] Missing .env: silent (expected)
- [ ] Rejects symlinks (mirrors existing helpers)
- [ ] Log message: `[INFO] Loading environment from .env`
## Done summary
Added safe .env file loading to entrypoint with CRLF stripping, set -e safety guards, and key-only logging for malformed lines to prevent value leakage.
## Evidence
- Commits: 8899f11, 6a17e1c, 107a607, 10fec15, 2e6e963
- Tests: bash -n entrypoint.sh, unit tests for _load_env_file
- PRs:
