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

### Directory Structure

```
~/.docker/
├── config.json
└── contexts/
    ├── meta/
    │   ├── <hash1>/meta.json   # context1
    │   ├── <hash2>/meta.json   # context2
    │   └── <hashN>/meta.json   # containai-docker (SSH socket)
    └── tls/
        └── <hash>/...          # TLS certs if any

~/.docker-cai/
├── config.json                  # Points to contexts/ here
└── contexts/
    ├── meta/
    │   ├── <hash1>/meta.json   # context1 (copied from host)
    │   ├── <hash2>/meta.json   # context2 (copied from host)
    │   └── <hashN>/meta.json   # containai-docker (Unix socket - DIFFERENT)
    └── tls/
        └── <hash>/...          # TLS certs if any
```

### Sync Logic

```bash
# Host → ContainAI direction
for context in ~/.docker/contexts/meta/*/; do
    context_name=$(get_context_name "$context")
    if [[ "$context_name" != "containai-docker" ]]; then
        rsync -a "$context" ~/.docker-cai/contexts/meta/
    fi
done

# ContainAI → Host direction
for context in ~/.docker-cai/contexts/meta/*/; do
    context_name=$(get_context_name "$context")
    if [[ "$context_name" != "containai-docker" ]]; then
        # Only sync if not already in host (new context created in container)
        rsync -a --ignore-existing "$context" ~/.docker/contexts/meta/
    fi
done
```

### Watcher Implementation

```bash
_cai_watch_docker_contexts() {
    local host_dir="$HOME/.docker/contexts"
    local cai_dir="$HOME/.docker-cai/contexts"

    if command -v inotifywait &>/dev/null; then
        # Linux: use inotifywait
        inotifywait -m -r -e create,delete,modify "$host_dir" "$cai_dir" |
        while read -r dir event file; do
            _cai_handle_context_change "$dir" "$event" "$file"
        done
    elif command -v fswatch &>/dev/null; then
        # macOS: use fswatch
        fswatch -r "$host_dir" "$cai_dir" |
        while read -r path; do
            _cai_handle_context_change_path "$path"
        done
    else
        _cai_warn "No file watcher available (need inotifywait or fswatch)"
        return 1
    fi
}
```

### Integration Points

1. **`cai setup`**: Creates initial `~/.docker-cai/` structure and `containai-docker` context
2. **`cai start`**: Starts the context sync watcher in background
3. **`cai stop`**: Stops the watcher
4. **Devcontainer feature**: Uses `~/.docker-cai/` via `DOCKER_CONFIG`

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
