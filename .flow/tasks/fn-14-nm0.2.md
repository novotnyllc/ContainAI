# fn-14-nm0.2 Refactor WSL2 setup for isolated Docker

## Description

Refactor `_cai_setup_wsl2()` to use a completely isolated Docker daemon instead of modifying the system's `/etc/docker/daemon.json`. Merge relevant logic from `scripts/install-containai-docker.sh`. Support upgrades by cleaning up old paths.

**Size:** M
**Files:** `src/lib/setup.sh`

## Current State

WSL2 setup (`setup.sh:844-931`) currently:
1. Installs Sysbox
2. Modifies `/etc/docker/daemon.json` to add sysbox-runc runtime
3. Creates a systemd drop-in to add a second socket listener
4. Creates `containai-secure` context

This still touches system Docker config.

## Approach

1. **Clean up legacy paths first** (support upgrades):
   - Remove old socket `/var/run/docker-containai.sock` if exists
   - Remove old context `containai-secure` if exists
   - Remove old drop-in `/etc/systemd/system/docker.service.d/containai-socket.conf` if exists
2. Create `/etc/containai/docker/daemon.json` with sysbox-runc runtime configured
3. Create `/etc/systemd/system/containai-docker.service` systemd unit (not a drop-in to docker.service)
4. Start the isolated daemon on `/var/run/containai-docker.sock`
5. Create `containai-docker` context pointing to isolated socket

**Cleanup helper:** Create `_cai_cleanup_legacy_paths()` to be shared with Linux task

**Merge from `scripts/install-containai-docker.sh`:**
- `create_daemon_json()` logic → `_cai_create_isolated_daemon_json()`
- `create_systemd_service()` logic → `_cai_create_isolated_docker_service()`
- `create_directories()` logic → ensure data/exec-root dirs exist
- `verify_installation()` logic → integrate into `cai doctor`

**Unit file location:** `/etc/systemd/system/containai-docker.service`

**Reuse:**
- `_cai_install_sysbox()` - still needed for sysbox binaries
- `_cai_create_containai_context()` - update to use new socket/context name
- Use constants from `src/lib/docker.sh`: `$_CAI_CONTAINAI_DOCKER_UNIT`, `$_CAI_CONTAINAI_DOCKER_SOCKET`, `$_CAI_CONTAINAI_DOCKER_CONTEXT`

## Key Context

- **Pitfall (from memory)**: "daemon.json + -H flag conflict" - don't set `hosts` in both daemon.json AND `-H` flag
- **Pitfall (from memory)**: "Systemd drop-in ExecStart= clears then replaces" - but we're creating a new service, not a drop-in
- WSL2 systemd is quirky - use `Wants=` not `Requires=` for docker.socket dependency
- When removing sysbox-runc from system daemon.json, use `jq` to remove just the runtime entry, preserve other config

## Acceptance

- [ ] `_cai_setup_wsl2()` creates `/etc/containai/docker/daemon.json`
- [ ] `_cai_setup_wsl2()` creates unit file at `/etc/systemd/system/containai-docker.service`
- [ ] `_cai_setup_wsl2()` never adds to `/etc/docker/daemon.json`
- [ ] `_cai_setup_wsl2()` never modifies `docker.service` or its drop-ins
- [ ] **Old socket `/var/run/docker-containai.sock` removed if exists**
- [ ] **Old context `containai-secure` removed if exists**
- [ ] **Old drop-in `containai-socket.conf` removed if exists**
- [ ] Isolated Docker uses socket at `$_CAI_CONTAINAI_DOCKER_SOCKET`
- [ ] Context created as `$_CAI_CONTAINAI_DOCKER_CONTEXT` (value: `containai-docker`)
- [ ] Shared helper functions created for reuse with Linux task
- [ ] `cai setup --dry-run` on WSL2 shows cleanup + isolated paths
- [ ] **Running `cai setup` twice is idempotent**
- [ ] Integration test verifies isolation

## Done summary

TBD

## Evidence

- Commits:
- Tests:
- PRs:
