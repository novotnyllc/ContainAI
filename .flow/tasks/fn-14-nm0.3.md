# fn-14-nm0.3 Refactor Native Linux setup for isolated Docker

## Description

Refactor `_cai_setup_linux()` to use a completely isolated Docker daemon instead of modifying the system Docker. Complete the merge of `scripts/install-containai-docker.sh` and delete it. Support upgrades by cleaning up old paths.

**Size:** M
**Files:** `src/lib/setup.sh`, `scripts/install-containai-docker.sh` (delete)

## Current State

Native Linux setup (`setup.sh:1847-1998`) currently:
1. Installs Sysbox
2. Calls `_cai_configure_daemon_json "$_CAI_WSL2_DAEMON_JSON"` - modifies `/etc/docker/daemon.json`
3. Uses `/var/run/docker.sock` (system socket)
4. Creates `containai-secure` context pointing to system socket

This completely pollutes the system Docker.

## Approach

1. **Clean up legacy paths first** (support upgrades):
   - Use shared `_cai_cleanup_legacy_paths()` from task .2
   - Remove old socket `/var/run/docker-containai.sock` if exists
   - Remove old context `containai-secure` if exists
   - Remove old drop-in `/etc/systemd/system/docker.service.d/containai-socket.conf` if exists
2. Create `/etc/containai/docker/daemon.json` with full isolated config
3. Create `/etc/systemd/system/containai-docker.service` systemd unit
4. Start isolated daemon with unique data-root, exec-root, pidfile, socket
5. Create `containai-docker` context
6. Remove all calls to `_cai_configure_daemon_json` for system paths
7. **Delete `scripts/install-containai-docker.sh`** after verifying all logic is merged

**Unit file location:** `/etc/systemd/system/containai-docker.service`

**Reuse from fn-14-nm0.2:**
- `_cai_cleanup_legacy_paths()` - shared cleanup helper
- `_cai_create_isolated_daemon_json()` - shared helper
- `_cai_create_isolated_docker_service()` - shared helper
- Use constants from `src/lib/docker.sh`: `$_CAI_CONTAINAI_DOCKER_UNIT`, `$_CAI_CONTAINAI_DOCKER_*`

## Key Context

- **From practice-scout**: Use separate subnet for bridge (`172.30.0.0/16`) to avoid IP conflicts
- **From memory**: Sysbox should be configured with `configure_docker_daemon=false` during install
- The existing `install-containai-docker.sh` is the reference implementation - merge then delete

## Acceptance

- [ ] `_cai_setup_linux()` creates `/etc/containai/docker/daemon.json`
- [ ] `_cai_setup_linux()` creates unit file at `/etc/systemd/system/containai-docker.service`
- [ ] `_cai_setup_linux()` never calls `_cai_configure_daemon_json` with system paths
- [ ] `_cai_setup_linux()` never adds to `/etc/docker/daemon.json`
- [ ] **Old socket `/var/run/docker-containai.sock` removed if exists**
- [ ] **Old context `containai-secure` removed if exists**
- [ ] **Old drop-in `containai-socket.conf` removed if exists**
- [ ] Isolated Docker uses data-root at `$_CAI_CONTAINAI_DOCKER_DATA`
- [ ] Isolated Docker uses socket at `$_CAI_CONTAINAI_DOCKER_SOCKET`
- [ ] Bridge network uses non-conflicting subnet
- [ ] `scripts/install-containai-docker.sh` is deleted
- [ ] `cai setup --dry-run` on Linux shows cleanup + isolated paths
- [ ] **Running `cai setup` twice is idempotent**

## Done summary
Refactored `_cai_setup_linux()` to use completely isolated Docker daemon. The function now creates `/etc/containai/docker/daemon.json` with isolated paths (data-root, exec-root, socket) and a separate subnet (172.30.0.1/16). Creates a standalone systemd unit `containai-docker.service` instead of modifying system Docker. Cleans up legacy paths (old socket, context, drop-in) on upgrade. The `scripts/install-containai-docker.sh` script has been deleted with its logic merged into setup.sh.
## Evidence
- Commits: 53aa3a188b6e9e2057d21b266c5c9afac09f5d02
- Tests: shellcheck -x src/lib/setup.sh, grep verification of acceptance criteria
- PRs:
