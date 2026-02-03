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

- [x] `~/.docker-cai/contexts/` mirrors `~/.docker/contexts/` (except containai-docker)
- [x] New contexts in either dir sync to the other
- [x] `containai-docker` context is NOT synced (different socket paths)
- [x] Watcher uses inotifywait (Linux) or fswatch (macOS)
- [x] Deletions sync correctly (removes from other side)
- [x] TLS certs sync along with context metadata
- [x] Graceful handling when watcher tools not installed
- [x] Unit tests for sync logic
- [ ] Integration test verifying sync behavior (deferred - requires Docker)

## Done summary

Implemented Docker context sync library at `src/lib/docker-context-sync.sh` with:

1. **`_cai_sync_docker_contexts_once()`** - One-time bidirectional sync between `~/.docker/contexts` and `~/.docker-cai/contexts`. Handles both metadata and TLS certs. Correctly removes deleted contexts from target.

2. **`_cai_create_containai_docker_context()`** - Creates container-local `containai-docker` context using `unix:///var/run/docker.sock` (vs host SSH socket).

3. **`_cai_watch_docker_contexts()`** - Continuous file watcher using `inotifywait` (Linux) or `fswatch` (macOS). Gracefully handles missing tools.

4. **`_cai_is_containai_docker_context()`** - Identifies containai-docker context by parsing meta.json.

Key design decisions:
- The `containai-docker` context is explicitly excluded from sync because host and container need different socket paths
- Sync is bidirectional to support contexts created in either environment
- TLS certificates are synced alongside context metadata
- Watcher runs in background by default, foreground mode available

## Evidence
- Commits: (pending)
- Tests: tests/unit/test-docker-context-sync.sh (10 tests, all passing)
- PRs:
