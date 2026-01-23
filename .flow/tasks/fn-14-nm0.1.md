# fn-14-nm0.1 Unify Docker path constants

## Description

Consolidate all Docker path constants into a single authoritative location and standardize on the `containai-docker` naming convention.

**Size:** S
**Files:** `src/lib/docker.sh`, `src/lib/setup.sh`

## Current State

Constants are scattered and inconsistent:
- `setup.sh:58`: `_CAI_SECURE_SOCKET="/var/run/docker-containai.sock"`
- `setup.sh:61`: `_CAI_WSL2_DAEMON_JSON="/etc/docker/daemon.json"` (points to system!)
- `docker.sh:306-309`: `_CAI_CONTAINAI_DOCKER_*` constants (correct naming)
- `scripts/install-containai-docker.sh:20-30`: Local `CAI_DOCKER_*` constants

## Approach

1. Keep constants in `src/lib/docker.sh:306-309` as the single source of truth
2. Remove duplicate constants from `setup.sh`
3. Update all references to use the docker.sh constants
4. Ensure docker.sh is sourced before setup.sh in containai.sh

**Pattern to follow:** Update `src/lib/docker.sh:306-309`:
```bash
_CAI_CONTAINAI_DOCKER_SOCKET="/var/run/containai-docker.sock"
_CAI_CONTAINAI_DOCKER_CONTEXT="containai-docker"
_CAI_CONTAINAI_DOCKER_CONFIG="/etc/containai/docker/daemon.json"
_CAI_CONTAINAI_DOCKER_DATA="/var/lib/containai-docker"
```

Add missing constants:
```bash
_CAI_CONTAINAI_DOCKER_EXEC="/var/run/containai-docker"
_CAI_CONTAINAI_DOCKER_PID="/var/run/containai-docker.pid"
_CAI_CONTAINAI_DOCKER_BRIDGE="cai0"
_CAI_CONTAINAI_DOCKER_SERVICE="containai-docker.service"
_CAI_CONTAINAI_DOCKER_UNIT="/etc/systemd/system/containai-docker.service"
```

## Key Context

- **Pitfall**: The `_CAI_WSL2_DAEMON_JSON="/etc/docker/daemon.json"` constant is THE BUG - it points to system Docker config
- Remove `_CAI_SECURE_SOCKET` and `_CAI_WSL2_DAEMON_JSON` from setup.sh entirely
- Context name must be `containai-docker` (not `docker-containai`)
- Service name must include `.service` suffix for clarity

## Acceptance

- [ ] All Docker path constants defined in `src/lib/docker.sh` only
- [ ] No Docker path constants in `src/lib/setup.sh`
- [ ] Constants follow `_CAI_CONTAINAI_DOCKER_*` naming pattern
- [ ] `_CAI_CONTAINAI_DOCKER_CONTEXT="containai-docker"` (not docker-containai)
- [ ] `_CAI_CONTAINAI_DOCKER_SERVICE="containai-docker.service"` (with .service suffix)
- [ ] `_CAI_CONTAINAI_DOCKER_UNIT="/etc/systemd/system/containai-docker.service"`
- [ ] All constants point to ContainAI-isolated paths (never `/etc/docker/`, never `/var/lib/docker/`)
- [ ] `grep -r "etc/docker/daemon.json" src/lib/setup.sh` returns no results
- [ ] `shellcheck -x src/lib/docker.sh` passes

## Done summary
Unified all Docker path constants into src/lib/docker.sh as single source of truth. Added 5 new constants (EXEC, PID, BRIDGE, SERVICE, UNIT). Changed context name from docker-containai to containai-docker. Removed _CAI_SECURE_SOCKET and _CAI_WSL2_DAEMON_JSON from setup.sh. Updated all references to use docker.sh constants.
## Evidence
- Commits: c96274c, a8b249b, dbc15fb
- Tests: shellcheck -x src/lib/docker.sh
- PRs:
