# fn-34-fk5 One-Shot Execution & Container Lifecycle

## Overview

Enhance container lifecycle management with session-aware operations and garbage collection. This epic consolidates remaining work from fn-12-css (exec), fn-18-g96 (container UX), and fn-19-qni (lifecycle/cleanup).

**Key Goals:**
1. Implement session detection to warn before stopping containers with active sessions
2. Add `cai status` to show container state and active sessions
3. Add `cai gc` to clean up stale containers/images
4. Ensure stdio/stderr and exit code passthrough work correctly

**Breaking Changes:** None. All existing behavior preserved.

## Scope

### In Scope
- **stdio/stderr passthrough verification**: Ensure proper TTY allocation
- **Exit code passthrough verification**: Validate remote exit codes returned correctly
- **Session detection**: Best-effort detection of SSH connections and PTYs
- **`cai stop` session warning**: Warn when active sessions detected, `--force` to skip
- **`cai stop --export`**: Run export before stopping (mutually exclusive with `--all`)
- **`cai status` command**: Show container status, uptime, and session info
- **`cai gc` command**: Prune stale containers/images with configurable retention
- **Shell completion updates**: Update completion for new commands/flags
- **Documentation**: Container lifecycle and alias documentation

### Out of Scope (already implemented or superseded)
- `cai exec` command (already implemented in `src/containai.sh`)
- `--container` parameter (already implemented in all commands)
- Workspace state persistence (superseded by fn-36-rb7)
- Container naming (superseded by fn-36-rb7)
- `--reset` flag (already implemented - generates new volume name)
- Default agent configuration (already implemented via `_containai_resolve_agent`)

## Approach

### Exit Codes (from src/lib/ssh.sh)

Actual exit code constants:
- 0: Success (`$_CAI_SSH_EXIT_SUCCESS`)
- 10: Container not found (`$_CAI_SSH_EXIT_CONTAINER_NOT_FOUND`)
- 11: Container start failed (`$_CAI_SSH_EXIT_CONTAINER_START_FAILED`)
- 12: SSH setup failed (`$_CAI_SSH_EXIT_SSH_SETUP_FAILED`)
- 13: SSH connection failed (`$_CAI_SSH_EXIT_SSH_CONNECT_FAILED`)
- 14: Host key mismatch (`$_CAI_SSH_EXIT_HOST_KEY_MISMATCH`)
- 15: Container is foreign (`$_CAI_SSH_EXIT_CONTAINER_FOREIGN`)
- 1-255: Passthrough from remote command (when SSH succeeds)

### Session Detection

Best-effort detection using existing helpers. Returns "unknown" when detection fails or tools unavailable.

**Key behaviors:**
- Uses `_cai_timeout` wrapper from `src/lib/docker.sh`
- Uses context-aware docker commands
- Checks for `ss` availability inside container, returns "unknown" (exit 2) if missing
- Returns: 0 = has sessions, 1 = no sessions, 2 = unknown

### `cai stop` Enhancements

**Session Warning:**
- Before stopping, call `_cai_detect_sessions`
- If sessions detected and interactive TTY, prompt for confirmation
- `--force` flag skips session check
- If detection returns "unknown", proceed without warning

**Export Before Stop:**
- `cai stop --export` runs export first, then session check, then stops
- `--export` is mutually exclusive with `--all` (error if both specified)
- Calls `_containai_export_cmd --container "$name"` (export resolves context internally)
- Export failure prevents stop (unless `--force`)

### `cai status` Command

Show container status with best-effort resource info:

```
$ cai status
Container: containai-myproject-abc123
  Status: running
  Uptime: 3d 4h 12m
  Image: ghcr.io/org/containai:agents-latest

  Sessions (best-effort):
    SSH connections: 2
    Active terminals: 3

  Resource Usage:
    Memory: 1.2GB / 4.0GB (30%)
    CPU: 5.2%
```

**Required fields:** container name, status, image
**Best-effort fields (5s timeout via `_cai_timeout`):** uptime, sessions, memory, cpu
**Flags:** `--json`, `--workspace`, `--container`

### `cai gc` Command (Garbage Collection)

Prune stale ContainAI resources:

```bash
cai gc                    # Interactive: show candidates and confirm
cai gc --dry-run          # Preview without removing
cai gc --force            # Skip confirmation
cai gc --age 7d           # Age-based pruning
cai gc --images           # Also prune unused images
```

**Staleness Metric:**
- Stopped containers (`status=exited`): use `.State.FinishedAt`
- Never-ran containers (`status=created`): use `.Created` timestamp
- Age calculated from current time minus the relevant timestamp

**Cross-Platform Timestamp Parsing:**
Use Python for portable RFC3339 parsing (both Linux and macOS):
```bash
_cai_parse_timestamp() {
    python3 -c "from datetime import datetime; import sys; ..." "$ts"
}
```

**Protection Rules:**
1. Never prune running containers
2. Never prune containers with `containai.keep=true` label
3. Only prune containers with `containai.managed=true` label
4. Operates on current Docker context only

**Image Pruning (`--images`):**
Prune unused images matching these exact prefixes:
- `containai:*` (local builds)
- `ghcr.io/containai/*` (official registry)

Pattern: `grep -E '^(containai:|ghcr\.io/containai/)'`
Only remove images NOT in use by any container (running or stopped).

## Tasks

### fn-34-fk5.2: Verify stdio/stderr passthrough
Verify `_cai_ssh_run` properly allocates TTY and streams output.

### fn-34-fk5.3: Verify exit code passthrough
Verify remote command exit codes match the constants defined above.

### fn-34-fk5.4: Implement session detection
Create `_cai_detect_sessions()` using context-aware docker, `_cai_timeout`, and `ss` availability check.

### fn-34-fk5.5: Add session warning to cai stop
Integrate session detection; add `--force` flag to skip warning.

### fn-34-fk5.6: Implement cai status command
New command showing container state and best-effort session/resource info.

### fn-34-fk5.7: Document container lifecycle behavior
Write clear documentation on create/start/stop/destroy lifecycle.

### fn-34-fk5.8: Add --export flag to cai stop
Run export before stopping using `--container` flag only. Mutually exclusive with `--all`.

### fn-34-fk5.9: Implement cai gc command
Garbage collection with cross-platform timestamp parsing, includes both exited and created containers. Image pruning uses explicit prefixes.

### fn-34-fk5.11: Update shell completion
Update completion for `cai status`, `cai gc`, and new flags.

### fn-34-fk5.12: Document handy aliases
Add alias documentation with quoting examples.

## Test Strategy

### Unit Tests (tests/unit/)
- `test-session-detection.sh`: Mock `ss` availability and outputs
- `test-gc-candidate-selection.sh`: Verify protection rules and age filtering
- `test-timestamp-parsing.sh`: Cross-platform timestamp parsing

### Integration Tests (tests/integration/)
- `test-stop-session-warning.sh`: Verify warning prompt in interactive mode
- `test-gc-e2e.sh`: Create test containers, verify GC respects rules

## Acceptance Criteria

- [ ] stdio/stderr streams to host terminal correctly
- [ ] Exit codes from remote commands returned correctly (0-255)
- [ ] SSH/container errors return correct codes (10-15)
- [ ] Session detection identifies SSH connections and PTYs
- [ ] Session detection returns "unknown" when `ss` unavailable
- [ ] `cai stop` warns when sessions detected (unless `--force`)
- [ ] `cai stop --export` exports using `--container` flag, then warns, then stops
- [ ] `cai stop --export --all` returns error (mutually exclusive)
- [ ] `cai status` shows container state and best-effort session info
- [ ] `cai gc` prunes stale containers respecting protection rules
- [ ] `cai gc` includes both exited and created containers
- [ ] `cai gc` uses cross-platform timestamp parsing
- [ ] `cai gc --dry-run` shows candidates without removing
- [ ] `cai gc --images` prunes only `containai:*` and `ghcr.io/containai/*` images not in use
- [ ] Shell completion updated for new commands/flags
- [ ] Documentation includes lifecycle and alias docs

## Supersedes

- **fn-12-css**: Remaining exec-related tasks
- **fn-19-qni**: `cai gc`, lifecycle management tasks

## Dependencies

- **fn-36-rb7** (should complete first): CLI UX consistency, workspace state
- **fn-31-gib**: Import reliability
- **fn-42-cli-ux-fixes-hostname-reset-wait-help**: CLI UX fixes

## References

- Existing SSH execution: `src/lib/ssh.sh:_cai_ssh_run`
- Timeout wrapper: `src/lib/docker.sh:_cai_timeout`
- Exit code constants: `src/lib/ssh.sh:1844-1850`
