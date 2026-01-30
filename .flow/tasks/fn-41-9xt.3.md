# fn-41-9xt.3 Update all lib files for verbose state

## Description
Update all library files to use the global verbose state. Gate direct `[INFO]` prints. Remove `quiet` gating around warnings (warnings should always emit).

**Size:** L
**Files:** All files in `src/lib/` plus `src/containai.sh`

## Files to Audit and Update

All files with direct `[INFO]`/progress output need gating:

1. **src/lib/ssh.sh** - SSH connection messages
   - `_cai_ssh_shell()` - has quiet param, simplify
   - `_cai_ssh_connect_with_retry()` - has quiet param
   - `_cai_ssh_run()` - has quiet param
   - Connection message at ~line 1877-1878

2. **src/lib/container.sh** - container lifecycle messages

3. **src/lib/import.sh** - import progress
   - Has local `_import_info()` wrapper that calls `_cai_info` - should work automatically

4. **src/lib/export.sh** - export progress

5. **src/lib/setup.sh** - setup progress messages

6. **src/lib/config.sh** - config management messages

7. **src/lib/links.sh** - symlinks messages

8. **src/lib/env.sh** - environment messages

9. **src/lib/version.sh** - version/update messages

10. **src/lib/uninstall.sh** - uninstall messages

11. **src/lib/doctor.sh** - diagnostic messages
    - **EXEMPT**: doctor is always verbose, but still need to ensure it calls `_cai_set_verbose`

12. **src/containai.sh** - main CLI direct prints
    - Replace `echo "[INFO] ..."` with `_cai_info "..."`
    - Or wrap in `if _cai_is_verbose; then ... fi`

## Approach

1. **Remove quiet parameter gating** where `_cai_info` is now auto-gated:
   - Find: `if [[ "$quiet" != "true" ]]; then _cai_info`
   - Replace: just `_cai_info` (it self-gates now)

2. **Warnings always emit** - remove quiet gating around warnings:
   - Find: `if [[ "$quiet" != "true" ]]; then _cai_warn`
   - Replace: unconditional `_cai_warn`

3. **Direct [INFO] prints**:
   - Replace `echo "[INFO] ..."` with `_cai_info "..."`
   - Replace `printf "[INFO] ...` with `_cai_info "..."`

4. **Test commands:**
   - `cai shell /tmp/test` should be silent
   - `cai shell /tmp/test --verbose` shows connection messages

## Key context

Current pattern checks `[[ "$quiet" != "true" ]]` before emitting. After task 1, `_cai_info()` is self-gating, so these explicit checks become redundant.

**Important:** `cai ssh` is a management command for SSH key cleanup, not for connecting to containers. The SSH connection messages are triggered by `cai shell` and `cai exec`.

## Acceptance
- [x] `cai shell <path>` is silent by default (no "Connecting..." message)
- [x] `cai shell <path> --verbose` shows connection messages
- [x] `cai exec <container> <cmd>` is silent by default
- [x] `cai exec <container> <cmd> --verbose` shows status messages
- [x] All direct `[INFO]` prints in containai.sh are gated
- [x] All lib files audited for direct prints
- [x] Warnings always emit (no quiet gating around `_cai_warn`)
- [x] shellcheck passes on all modified files

## Done summary
# Task fn-41-9xt.3 Complete

## Summary
Updated all library files to use the global verbose state from task 1. Key changes:

### container.sh
- Converted all direct `echo "[WARN]"` to `_cai_warn()` calls:
  - Isolation status detection messages
  - Force flag bypass warnings
  - Context validation warnings
  - Interactive selection warnings
- Converted `echo "[ERROR]"` + `echo "[HINT]"` patterns to `_cai_error()` + `_cai_warn()` for consistency

### Previously completed (verified still correct)
- ssh.sh: Redundant `quiet != true` checks around `_cai_info` removed (now self-gating)
- ssh.sh: Quiet gating around `_cai_warn` removed so warnings always emit
- containai.sh: Direct `echo "[INFO]"` replaced with `_cai_info()` calls
- links.sh, export.sh: Local `_*_info()` helpers delegate to `_cai_info()` when available
- config.sh: Direct `[INFO]` print converted to `_cai_info()`
- setup.sh: Updated Lima template output to use `_cai_info()` when available in subshell

### Import.sh exceptions (intentional)
- Lines 1761, 1768: Use `IMPORT_VERBOSE` flag because these run under POSIX sh inside the container, not bash host context. Cannot use `_cai_info()`.

## Verification
- shellcheck passes on all modified files
- No direct `echo "[WARN]"` or `echo "[INFO]"` patterns remain in container.sh
- No `quiet != true` gating patterns around `_cai_info`/`_cai_warn` remain
- Links.sh quiet gating for command output (not logging) is intentional and correct
## Summary
Updated all library files to use the global verbose state from task 1. Key changes:

### ssh.sh
- Removed redundant `quiet != true` checks around `_cai_info` calls (now self-gating)
- Removed quiet gating around `_cai_warn` calls so warnings always emit
- Updated connection messages, auto-recovery messages, and retry warnings

### container.sh
- Converted direct `echo "[WARN]"` prints to `_cai_warn()` calls
- Converted progress messages (creating, starting, removing container) to `_cai_info()`
- Updated verbose info blocks to use `_cai_info()` instead of `printf "[INFO]"`
- Ensured warnings always emit regardless of quiet flag

### containai.sh
- Replaced all direct `echo "[INFO]"` with `_cai_info()` calls
- Converted error guidance messages to `_cai_warn()` (always emit)
- Removed redundant `quiet_flag != true` checks around info/progress messages

### Other lib files
- **links.sh, export.sh**: Updated local `_*_info()` helpers to delegate to `_cai_info()` when available
- **config.sh**: Converted direct `[INFO]` print to `_cai_info()`
- **setup.sh**: Updated Lima template output to use `_cai_info()` when available in subshell

## Verification
- shellcheck passes on all modified files
- No direct `[INFO]` prints remain in containai.sh
- No quiet_flag gating patterns around echo/printf remain
## Evidence
- Commits:
- Tests: shellcheck -x passes on all src/*.sh src/lib/*.sh, No direct echo [WARN] patterns remain in container.sh, No quiet gating around _cai_info/_cai_warn remains, import.sh POSIX shell context exceptions documented
- PRs:
