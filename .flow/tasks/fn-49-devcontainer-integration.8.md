# fn-49-devcontainer-integration.8 Docker context sync watcher

## Description

Create a bidirectional sync mechanism between `~/.docker/contexts` and `~/.docker-cai/contexts` that keeps them in sync, with special handling for the `containai-docker` context which has different socket paths.

### Problem

The devcontainer needs Docker contexts from the host, but:
- Host's `containai-docker` context uses SSH socket (`ssh://user@host`)
- Container's `containai-docker` context needs Unix socket (`unix:///var/run/docker.sock`)
- Other contexts should be synced bidirectionally without modification

### Implementation

**Location**: `src/lib/docker-context-sync.sh`

### Core Functions

1. **`_cai_sync_docker_contexts_once()`**
   - One-time sync from source to target
   - Parameters: `$1` = source dir, `$2` = target dir, `$3` = direction (host-to-cai|cai-to-host)
   - Syncs all contexts except `containai-docker`
   - Creates target dirs if missing

2. **`_cai_create_containai_docker_context()`**
   - Creates the `containai-docker` context in `~/.docker-cai/contexts/`
   - Uses Unix socket path (`unix:///var/run/docker.sock`)
   - Called during setup, not during sync

3. **`_cai_watch_docker_contexts()`**
   - Starts continuous file watcher
   - Uses `inotifywait` on Linux, `fswatch` on macOS
   - Watches both directories for changes
   - Triggers sync on create/delete/modify

4. **`_cai_is_containai_docker_context()`**
   - Check if a context path is the special `containai-docker` context
   - Returns 0 if yes, 1 if no

## Acceptance

- [ ] `~/.docker-cai/contexts/` mirrors `~/.docker/contexts/` (except containai-docker)
- [ ] New contexts in either dir sync to the other
- [ ] `containai-docker` context is NOT synced (different socket paths)
- [ ] Watcher uses inotifywait (Linux) or fswatch (macOS)
- [ ] Deletions sync correctly (removes from other side)
- [ ] TLS certs sync along with context metadata
- [ ] Graceful handling when watcher tools not installed
- [ ] Unit tests for sync logic
- [ ] Integration test verifying sync behavior

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
