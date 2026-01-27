# Fix SSH reliability, import defaults, doctor UX, and sysbox URLs

## Overview

Batch of reliability and UX fixes addressing critical SSH connection failures, import system improvements, doctor command restructuring, and sysbox URL updates.

**Priority:** SSH fix is CRITICAL - users cannot connect to freshly created containers.

## Scope

1. **SSH reliability** - Fix double SSH setup causing "Permission denied" after `cai shell --fresh`
2. **Import defaults** - Remove `~/.ssh` from defaults, skip profile credentials, fix base64 errors
3. **Doctor UX** - Restructure `--fix`/`--repair` into `cai doctor fix` subcommand hierarchy
4. **Container/volume visibility** - Print names clearly in `cai run/shell` output
5. **Docker context auto-repair** - Detect and fix `containai-docker` context reverting to `unix://`
6. **Sysbox URLs** - Update to new ContainAI GitHub release URLs

## Approach

### SSH Double Setup Fix
- Root cause: `_cai_ssh_shell()` at `src/lib/ssh.sh:1659` calls `_cai_setup_container_ssh()` again when `force_update=true`, even though `container.sh:2263` already called it
- Fix: Make `_cai_ssh_shell()` smarter - only call setup if config actually missing, ignore `force_update` for SSH setup (it's meant for other things)
- Also ensure `cai setup` doesn't regenerate keys that already exist (verify idempotency at `ssh.sh:153-233`)

### Import System Changes
- Remove `~/.ssh/*` entries from `_IMPORT_SYNC_MAP` at `import.sh:378-383`
- For `~/.claude/.credentials.json`: skip import if source path is `$HOME/.claude/` (user profile) - keep symlink for volume mount
- Same for `~/.codex/auth.json` - skip if from `$HOME/.codex/`
- For `~/.copilot/config.json`: ensure minimum JSON structure `{"trusted_folders":["/home/agent/workspace"],"editor_version":"vscode-1.99.0"}`
- Suppress "source not found/missing" unless `--verbose` flag
- Debug the `base64: truncated input` error at `import.sh:2600` - likely buffer/encoding issue

### Doctor Restructure
- Change from: `cai doctor --fix`, `cai doctor --repair`
- To: `cai doctor fix [--all | volume [--all|<name>] | container [--all|<name>]]`
- List known volumes/containers when user doesn't specify one
- Operations: volume fix = permission repair; container fix = SSH config refresh

### Container/Volume Name Visibility
- Add clear output in `cai run` and `cai shell` showing:
  ```
  Container: containai-0898484b57d8
  Volume: cai-dat
  ```

### Docker Context Auto-Repair
- Existing detection at `docker.sh:514-539` sets `_CAI_CONTAINAI_CONTEXT_ERROR="wrong_endpoint"`
- Add auto-repair when detected (recreate context with correct endpoint)
- Run check at start of context-dependent operations, not on every command

## Quick commands

```bash
# Test SSH reliability after fix
cai shell --fresh --data-volume test-vol && cai shell

# Test doctor fix
cai doctor fix --all
cai doctor fix volume --all
cai doctor fix container containai-XXXX

# Test import (verbose to see what's skipped)
cai run --verbose echo "import test"
```

## Acceptance

- [ ] `cai shell --fresh` followed by `cai shell` connects successfully (no Permission denied)
- [ ] SSH setup messages appear only ONCE, not twice
- [ ] `cai setup` preserves existing SSH keys (doesn't regenerate)
- [ ] `~/.ssh` is NOT imported by default (user can add via config if wanted)
- [ ] Claude/Codex credentials from user profile are NOT imported (symlink still works)
- [ ] Copilot config.json gets minimum trusted_folders structure
- [ ] "source not found" messages only appear with `--verbose`
- [ ] No "base64: truncated input" errors during import
- [ ] `cai doctor fix --all` works
- [ ] `cai doctor fix volume <name>` works (lists volumes if name omitted)
- [ ] `cai run/shell` prints container and volume names
- [ ] Docker context auto-repairs when detected as wrong endpoint

## References

- SSH double setup: `src/lib/ssh.sh:1659`, `src/lib/container.sh:2263`
- Import sync map: `src/lib/import.sh:352-479`
- Doctor functions: `src/lib/doctor.sh`
- Context validation: `src/lib/docker.sh:514-539`
- Sysbox URL resolution: `src/lib/setup.sh:650-780`

## Dependencies

- fn-28-5do (Fix fn-27-hbi Bugs) - Related SSH fixes, should coordinate
