# fn-34-fk5.6: Implement cai status command

## Goal
New command to show container status, uptime, and session information.

## Output Format
```
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

## Implementation
1. Add `_containai_status_cmd` function to `src/containai.sh`
2. Add routing in main command handler
3. Use `docker inspect` for basic info (required)
4. Use `_cai_timeout 5 docker stats --no-stream` for resources (best-effort)
5. Use `_cai_detect_sessions` for session info (best-effort)

## Fields
- Required: container name, status, image
- Best-effort: uptime, sessions, memory, cpu

## Files
- `src/containai.sh`: Add `_containai_status_cmd` and routing

## Acceptance
- [x] Shows container name, status, image (required)
- [x] Shows uptime, sessions, resources (best-effort, 5s timeout)
- [x] `--json` outputs valid JSON
- [x] Works with `--workspace` and `--container` flags
- [x] Graceful degradation on timeout

## Done summary
# Task fn-34-fk5.6: Implement cai status command

## Implementation Summary

Added `cai status` command to show container status, uptime, and session information.

### Changes Made

1. **Added `_containai_status_help` function** (after `_containai_stop_help`):
   - Help text documenting usage, options, and examples

2. **Added `_containai_status_cmd` function** (after `_containai_stop_cmd`):
   - Argument parsing for `--workspace`, `--container`, `--json`, `--verbose`
   - Container resolution via workspace state or explicit `--container`
   - Uses `_cai_find_container_by_name` for context-aware lookup
   - Required fields: container name, status, image (via `docker inspect`)
   - Best-effort fields with 5s timeout:
     - Uptime calculation from StartedAt timestamp
     - Memory/CPU usage via `docker stats --no-stream`
     - Session info via `_cai_detect_sessions`
   - Human-readable and JSON output formats

3. **Added routing in `containai()` function**:
   - Added `status)` case to route to `_containai_status_cmd`

4. **Updated `_containai_help()`**:
   - Added status to subcommands list

### Files Modified
- `src/containai.sh`

## Acceptance Criteria Met
- [x] Shows container name, status, image (required)
- [x] Shows uptime, sessions, resources (best-effort, 5s timeout via `_cai_timeout`)
- [x] `--json` outputs valid JSON
- [x] Works with `--workspace` and `--container` flags
- [x] Graceful degradation on timeout (fields simply omitted)
## Evidence
- Commits:
- Tests:
- PRs:
