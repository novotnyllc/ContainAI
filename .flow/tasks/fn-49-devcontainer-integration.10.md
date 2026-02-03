# fn-49-devcontainer-integration.10 Wire docker-context-sync into CLI lifecycle

## Description

Solve the WSL2/Windows context collision problem where symlinked `~/.docker/contexts` causes the `ssh://` URL to appear on both sides.

**Problem:**
- User's `~/.docker/contexts` is symlinked between Windows and WSL2
- `containai-docker` context uses `ssh://` endpoint
- This `ssh://` URL shows up on WSL2 side too (unnecessary SSH hop, friction)

**Solution:**
- Create separate `~/.docker-cai/` directory (not symlinked)
- **WSL2**: `containai-docker` → `unix:///var/run/containai-docker.sock`
- **Windows**: `containai-docker` → `ssh://user@wsl-host`
- **Continuous watcher** syncs user's other contexts `~/.docker/` → `~/.docker-cai/` (excluding `containai-docker`)
- Use `DOCKER_CONFIG=~/.docker-cai` to pick up the right context per-platform

**Size:** M

**Files:**
- `src/containai.sh` (add to library loading)
- `src/lib/docker-context-sync.sh` (add service management functions)
- `src/lib/setup.sh` (create platform-specific context + start sync service on WSL2)
- `src/lib/uninstall.sh` (stop service and cleanup)
- `src/lib/doctor.sh` (add sync service status check)

## Current State

Library exists at `src/lib/docker-context-sync.sh` with:
- `_cai_sync_docker_contexts_once()` - one-time sync (excludes `containai-docker`)
- `_cai_create_containai_docker_context()` - create container-local context
- `_cai_watch_docker_contexts()` - continuous watcher
- `_cai_stop_docker_context_watcher()` - cleanup

**Not loaded or called anywhere.**

## Integration Points

### 1. Load the library (`src/containai.sh`)

Add to `_containai_libs_exist()` check at line ~77:
```bash
&& [[ -f "$_CAI_SCRIPT_DIR/lib/docker-context-sync.sh" ]]
```

Add sourcing block after docker.sh:
```bash
# shellcheck source=lib/docker-context-sync.sh
if ! source "$_CAI_SCRIPT_DIR/lib/docker-context-sync.sh"; then ...
```

### 2. Setup integration (`src/lib/setup.sh`)

**WSL2 only** - after `_cai_setup_wsl2_windows_npipe_bridge()`:

```bash
# Create ~/.docker-cai/ with platform-specific containai-docker context
_cai_setup_docker_cai_dir "$dry_run"

# Initial sync of user's other contexts (excludes containai-docker)
_cai_sync_docker_contexts_once "$HOME/.docker/contexts" "$HOME/.docker-cai/contexts" "host-to-cai"

# Start persistent watcher service (runs continuously, syncs on every change)
_cai_start_context_sync_service
```

**macOS/Linux**: No sync needed - use Unix socket directly in `~/.docker/contexts`.

### 2a. Add inotify-tools to WSL2 dependencies

Add to `_cai_setup_wsl2()` tool checks (~line 1104):
```bash
if ! command -v inotifywait >/dev/null 2>&1; then
    missing_pkgs+=("inotify-tools")
fi
```

### 2b. Platform-specific containai-docker context

New function `_cai_setup_docker_cai_dir()`:

```bash
_cai_setup_docker_cai_dir() {
    local dry_run="${1:-false}"

    mkdir -p "$HOME/.docker-cai/contexts"

    if _cai_is_wsl2; then
        # WSL2: Unix socket (direct access)
        _cai_create_context_in_dir "$HOME/.docker-cai" "containai-docker" \
            "unix:///var/run/containai-docker.sock"
    fi
    # Windows side handled separately (by Windows install or manual)
}
```

### 2c. Persistent sync service (WSL2 only)

systemd user service at `~/.config/systemd/user/containai-context-sync.service`:
```ini
[Unit]
Description=ContainAI Docker Context Sync
After=default.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'source ~/.local/share/containai/containai.sh && _cai_watch_docker_contexts foreground'
Restart=on-failure

[Install]
WantedBy=default.target
```

New functions:
- `_cai_start_context_sync_service()` - Install and enable systemd user service
- `_cai_stop_context_sync_service()` - Stop and remove service
- `_cai_context_sync_service_status()` - Check if running

### 3. Uninstall integration (`src/lib/uninstall.sh`)

Add before Docker context removal (WSL2 only):
```bash
if _cai_is_wsl2; then
    _cai_stop_context_sync_service
    _cai_stop_docker_context_watcher
    rm -rf "$HOME/.docker-cai"
fi
```

## Key Decisions

1. **WSL2 only** - macOS/Linux don't have the symlink collision problem
2. **Separate directory** - `~/.docker-cai/` is NOT symlinked, platform-specific
3. **Continuous sync** - Watcher runs always, syncs on every file change (inotifywait)
4. **Don't touch `~/.docker/`** - User's shared contexts remain untouched
5. **systemd user service** - Survives reboots, auto-restarts on failure

## Testing Strategy

### Unit Tests (`tests/unit/test-docker-context-sync-service.sh`)

1. **Platform detection**
   - Service only starts on WSL2
   - macOS/Linux skip gracefully

2. **Context creation**
   - `_cai_setup_docker_cai_dir` creates correct context per platform
   - WSL2 gets `unix://` endpoint

3. **Service management**
   - `_cai_context_sync_service_status` returns correct codes
   - `_cai_stop_context_sync_service` is idempotent

### Integration Tests (`tests/integration/test-context-sync-service.sh`)

1. **Sync behavior**
   ```bash
   # Create test context in ~/.docker/contexts
   docker context create test-remote --docker "host=tcp://remote:2375"

   # Trigger sync
   _cai_sync_docker_contexts_once ~/.docker/contexts ~/.docker-cai/contexts host-to-cai

   # Verify synced (but containai-docker is NOT synced)
   grep -r "test-remote" ~/.docker-cai/contexts/
   ! grep -r "containai-docker" ~/.docker-cai/contexts/meta/*/meta.json | grep -q "ssh://"
   ```

2. **Uninstall cleanup**
   ```bash
   _cai_stop_context_sync_service
   rm -rf "$HOME/.docker-cai"
   [[ ! -d "$HOME/.docker-cai" ]]
   ```

### Manual Testing (WSL2)

- [ ] `cai setup` creates `~/.docker-cai/` with Unix socket context
- [ ] User's other contexts synced to `~/.docker-cai/`
- [ ] `containai-docker` in `~/.docker-cai/` has `unix://` (not `ssh://`)
- [ ] Watcher service running: `systemctl --user status containai-context-sync`
- [ ] Add context on host → appears in `~/.docker-cai/` within seconds
- [ ] `cai uninstall` removes service and `~/.docker-cai/`

## Acceptance

- [ ] `docker-context-sync.sh` sourced in `containai.sh`
- [ ] `_containai_libs_exist()` includes the new library
- [ ] WSL2: `cai setup` creates `~/.docker-cai/` with Unix socket `containai-docker`
- [ ] WSL2: User's other contexts synced from `~/.docker/`
- [ ] WSL2: Watcher service runs persistently (survives reboots)
- [ ] WSL2: `cai uninstall` stops service + removes `~/.docker-cai/`
- [ ] macOS/Linux: No sync service started (not needed)
- [ ] `inotify-tools` added to WSL2 dependency list
- [ ] `cai doctor` shows sync service status (WSL2 only)
- [ ] Operations respect `--dry-run` flag
- [ ] `shellcheck` passes
- [ ] Unit tests pass
- [ ] Integration tests pass

## Done summary
Wired docker-context-sync.sh into CLI lifecycle with full WSL2 integration: library loaded in containai.sh, service management functions for systemd user service, setup creates ~/.docker-cai/ with Unix socket context and starts persistent watcher, uninstall cleans up service and directory, doctor shows sync service status. All operations respect --dry-run and only activate on WSL2.
## Evidence
- Commits: 1db76073e68ff39e96f5df0d2ac2fde2709b5f08, 6885ada0dd5360e33db4e19b5f1e0ffe0ff4d52a, b23ed501ada5960ba47c51262a6fabb85cf64b27
- Tests: shellcheck -x src/*.sh src/lib/*.sh, bash -c 'source src/containai.sh && type _cai_sync_docker_contexts_once'
- PRs:
