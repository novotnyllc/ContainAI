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
- [ ] Shows container name, status, image (required)
- [ ] Shows uptime, sessions, resources (best-effort, 5s timeout)
- [ ] `--json` outputs valid JSON
- [ ] Works with `--workspace` and `--container` flags
- [ ] Graceful degradation on timeout
