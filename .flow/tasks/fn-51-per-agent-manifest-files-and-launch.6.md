# Task fn-51.6: Add user-defined manifest support via runtime hook

**Status:** pending
**Depends on:** fn-51.1, fn-51.3

## Objective

Allow users to add custom agent manifests that get processed at container startup with proper security constraints.

## Context

Users drop a TOML file in `~/.config/containai/manifests/`, run `cai import`, restart container - their agent just works. No Dockerfile knowledge needed.

## Implementation

1. Add user manifest directory to sync (in `00-common.toml`):
```toml
[[entries]]
source = ".config/containai/manifests"
target = "containai/manifests"
container_link = ".config/containai/manifests"
flags = "do"  # directory, optional
```

2. **Create runtime generator scripts** (in `src/container/lib/`):
   - `gen-user-links.sh` - creates symlinks for user manifest entries with validation
   - `gen-user-wrappers.sh` - generates functions to `/home/agent/.bash_env.d/containai-user-agents.sh`

3. **Install runtime generators in Dockerfile.agents:**
```dockerfile
# =============================================================================
# USER MANIFEST RUNTIME SUPPORT
# =============================================================================
RUN mkdir -p /usr/local/lib/containai
COPY src/container/lib/gen-user-links.sh /usr/local/lib/containai/
COPY src/container/lib/gen-user-wrappers.sh /usr/local/lib/containai/
RUN chmod +x /usr/local/lib/containai/*.sh
```

4. Update `containai-init.sh` (runs at container startup):
```bash
# After built-in setup, check for user manifests
USER_MANIFESTS="/mnt/agent-data/containai/manifests"
if [[ -d "$USER_MANIFESTS" ]] && ls "$USER_MANIFESTS"/*.toml >/dev/null 2>&1; then
    # Generate user symlinks (validates paths, logs errors)
    /usr/local/lib/containai/gen-user-links.sh "$USER_MANIFESTS"

    # Generate user launch wrappers (validates binaries, logs errors)
    /usr/local/lib/containai/gen-user-wrappers.sh "$USER_MANIFESTS"
fi
```

5. **Security constraints for user manifests:**

   a. Path validation for symlinks (in gen-user-links.sh):
   - `target` must resolve under `/mnt/agent-data` (use `verify_path_under_data_dir()` pattern)
   - `container_link` must be relative path under `/home/agent` with no `..` segments
   - Reject absolute paths for `container_link`

   b. TOML validation:
   - Invalid TOML syntax → log warning, skip file, continue
   - Missing required fields → log warning, skip entry, continue
   - Invalid flag characters → log warning, skip entry, continue

   c. Binary validation for wrappers (in gen-user-wrappers.sh):
   - Only generate wrapper if binary exists in PATH
   - Log info message if binary missing (not error)

6. **User link spec generation** (in gen-user-links.sh):
   - Generate `/mnt/agent-data/containai/user-link-spec.json`
   - **Schema must match built-in link-spec.json exactly:**
   ```json
   {
     "version": 1,
     "data_mount": "/mnt/agent-data",
     "home_dir": "/home/agent",
     "links": [
       {
         "link": "/home/agent/.myagent/config.json",
         "target": "/mnt/agent-data/myagent/config.json",
         "remove_first": 0
       }
     ]
   }
   ```
   - Fields per link:
     - `link`: Full absolute path to symlink in home dir
     - `target`: Full absolute path to target in data volume
     - `remove_first`: 1 if directory should be removed before linking, 0 otherwise

7. **Update link-repair.sh** to read both specs:
```bash
BUILTIN_SPEC="/usr/local/lib/containai/link-spec.json"
USER_SPEC="/mnt/agent-data/containai/user-link-spec.json"

# Process built-in links
process_link_spec "$BUILTIN_SPEC"

# Process user links if spec exists
[[ -f "$USER_SPEC" ]] && process_link_spec "$USER_SPEC"
```

## Acceptance Criteria

- [ ] User manifest directory synced to container
- [ ] Runtime generators created: `gen-user-links.sh`, `gen-user-wrappers.sh`
- [ ] Runtime generators installed in image at `/usr/local/lib/containai/`
- [ ] `containai-init.sh` checks for and processes user manifests
- [ ] User symlinks created at startup with path validation
- [ ] `target` paths validated to be under `/mnt/agent-data`
- [ ] `container_link` paths validated (relative, no `..`, under `/home/agent`)
- [ ] Invalid TOML files logged and skipped (don't block startup)
- [ ] Invalid entries logged and skipped (don't block other entries)
- [ ] User launch wrappers generated at startup (binary must exist)
- [ ] User link spec uses **same schema as built-in**: `{link, target, remove_first}`
- [ ] `link-repair.sh` updated to read both built-in and user link specs
- [ ] Empty directory doesn't cause errors
- [ ] Works without container rebuild

## Notes

- Runtime generators are lightweight (bash + parse-toml.py)
- Reuse existing validation patterns from containai-init.sh
- User wrappers go to separate file (`containai-user-agents.sh`) to avoid clobbering built-in
- Fail-safe: invalid manifests don't block startup, just log and skip
- Link spec schema: `link` (full symlink path), `target` (full target path), `remove_first` (0 or 1)
