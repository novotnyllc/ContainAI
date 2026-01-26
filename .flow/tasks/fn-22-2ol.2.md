# fn-22-2ol.2 Investigate symlinks.sh build failure

## Description
Investigate and fix the symlinks.sh build failure:
```
process "/bin/bash -o pipefail -c chmod +x /tmp/symlinks.sh && /tmp/symlinks.sh && rm /tmp/symlinks.sh" did not complete successfully: exit code: 1
```

**Size:** S
**Files:** `src/container/generated/symlinks.sh`, `src/container/Dockerfile.agents`

## Approach

- Reproduce failure in the correct user context (script runs as `agent` user, not root)
- Check `/mnt/agent-data` existence and ownership - most likely root cause is permissions
- Fix by ensuring `/mnt/agent-data` is created and owned by `agent:agent` before running symlinks.sh
- If needed, add a `USER root` step to `mkdir -p /mnt/agent-data && chown agent:agent /mnt/agent-data` then switch back

## Key context

- Script uses `#!/bin/sh` with `set -e` - any command failure exits
- **Critical**: Script runs as `USER agent` in Dockerfile.agents, but `/mnt` is typically root-owned
- If base/SDK image doesn't pre-create/chown `/mnt/agent-data`, `mkdir -p /mnt/agent-data/...` will fail under `set -e`
- Reproduce with matching context: `docker run --rm --user 1000:1000 -v $(pwd)/src/container/generated/symlinks.sh:/tmp/symlinks.sh ubuntu:22.04 sh -x /tmp/symlinks.sh`
- Referenced from `Dockerfile.agents:109-110`

## Acceptance
- [ ] Root cause identified (likely /mnt/agent-data permissions)
- [ ] Fix applied in Dockerfile.agents (create + chown /mnt/agent-data before symlinks.sh)
- [ ] Local docker build passes symlinks step
## Done summary
Fixed symlinks.sh build failure by ensuring /mnt/agent-data exists with correct ownership before running the script. Added USER root step to mkdir and chown the directory, then switch back to USER agent.
## Evidence
- Commits: a1f15a6228cd3c84c8e3b10fd06bb81e930981c0
- Tests: docker build --check -f src/container/Dockerfile.agents src/, shellcheck -x src/container/generated/symlinks.sh
- PRs:
