# fn-6-aaz.3 Implement env import core logic

## Description
Implement core env var import logic with proper permission handling and multiline warning formats.

**Size:** M  
**Files:** `agent-sandbox/lib/env.sh` (new file)

## Approach

- Create new `lib/env.sh` with `_containai_import_env()` function
- Validate var names, deduplicate allowlist
- Parse source .env file with CRLF stripping
- Read host env when enabled
- **Permission handling**: Write as root in helper, then chown 1000:1000 + chmod 600
- **Multiline warning format**:
  - File: `[WARN] line N: key 'FOO' skipped (multiline value)`
  - Host: `[WARN] source=host: key 'FOO' skipped (multiline value)`
- Stream via stdin, TOCTOU-safe atomic write
## Approach

- Create new `lib/env.sh` with `_containai_import_env()` function
- Validate var names against `^[A-Za-z_][A-Za-z0-9_]*$` - skip invalid with warning
- Deduplicate allowlist preserving first occurrence
- Parse source .env file with explicit rules (see epic spec)
- Read host env using `printenv` filtered by validated allowlist
- Merge sources (host takes precedence over file)
- **Log hygiene**: Never print values or raw lines - warn with line_number + key + reason only
- **Stream content via stdin** to avoid docker inspect exposure
- **TOCTOU-safe atomic write**:
  1. Verify mount point not symlink and is directory
  2. Verify target .env not symlink (if exists)
  3. Create temp via mktemp, verify not symlink
  4. Write, chmod 600, mv to final

## Key Context

- Use `printf '%s\n'` not `echo` (per conventions)
- Use `[OK]`, `[WARN]`, `[ERROR]` markers
- Pattern for stdin streaming: `printf '%s' "$content" | docker --context "$ctx" run --rm -i ...`
- Helper container uses `--user 1000:1000` and `--network=none`
## Approach

- Create new `lib/env.sh` with `_containai_import_env()` function
- Validate var names against `^[A-Za-z_][A-Za-z0-9_]*$` - skip invalid with warning
- Parse source .env file using explicit rules:
  - Accept `KEY=VALUE` lines (optionally `export ` prefix)
  - Ignore `#` comment lines and blank lines
  - Split on FIRST `=` only, preserve remainder as value
  - Skip multiline values with warning
  - Handle CRLF (strip `\r`)
- Read host env using `printenv` filtered by validated allowlist
- Merge sources (host takes precedence over file)
- **Stream content via stdin** (not `-e` args) to avoid docker inspect exposure
- Write atomically: `.env.tmp.$$` + `chmod 600` + `mv`
- Reject if target is symlink

## Key Context

- Use `printf '%s\n'` not `echo` (per conventions)
- Use `[OK]`, `[WARN]`, `[ERROR]` markers
- Symlink validation: reject symlinks on both source .env file and target
- Pattern for stdin streaming: `printf '%s' "$content" | docker run --rm -i ...`
## Approach

- Create new `lib/env.sh` with `_containai_import_env()` function
- Parse source .env file using safe line-by-line reading (no eval/source)
- Read from host env using `printenv` filtered by allowlist
- Merge sources (host takes precedence over file)
- Write atomically: temp file + `mv` rename
- Set permissions `chmod 600`
- Skip multiline values with warning

## Key Context

- Use `printf '%s\n'` not `echo` (per conventions)
- Use `[OK]`, `[WARN]`, `[ERROR]` markers
- Docker env-file format: no quotes, literal values
- Symlink validation: reject symlinks on source .env file
## Acceptance
- [ ] `_containai_import_env` function exists in `lib/env.sh`
- [ ] Takes Docker context as parameter
- [ ] Var names validated against `^[A-Za-z_][A-Za-z0-9_]*$`
- [ ] Allowlist deduplicated preserving order
- [ ] `env_file` path validated as workspace-relative (absolute rejected with error)
- [ ] `env_file` missing/unreadable: **hard error** when set
- [ ] CRLF stripping in file parser
- [ ] Host env multiline check
- [ ] **Multiline warning format**: file=`line N: key 'X'`, host=`source=host: key 'X'`
- [ ] **Log hygiene**: Never prints values or raw lines
- [ ] **Permission handling**: Write as root, chown 1000:1000, chmod 600
- [ ] Streams content via stdin (no values in docker `-e` args)
- [ ] TOCTOU-safe atomic write with symlink checks
- [ ] Missing vars logged as `[WARN]` (key only), not fatal
- [ ] Empty allowlist skips with `[INFO]`
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
