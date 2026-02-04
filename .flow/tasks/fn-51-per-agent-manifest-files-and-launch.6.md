# Task fn-51.6: Add user-defined manifest support via runtime hook

**Status:** pending
**Depends on:** fn-51.1, fn-51.3

## Objective

Allow users to add custom agent manifests that get processed at container startup.

## Context

Users drop a TOML file in `~/.config/containai/manifests/`, run `cai import`, restart container - their agent just works. No Dockerfile knowledge needed.

## Implementation

1. Add user manifest directory to sync (in common.toml):
```toml
[[entries]]
source = ".config/containai/manifests"
target = "containai/manifests"
container_link = ".config/containai/manifests"
flags = "do"  # directory, optional
```

2. Update `containai-init.sh` (runs at container startup):
```bash
# After built-in setup, check for user manifests
USER_MANIFESTS="/mnt/agent-data/containai/manifests"
if [[ -d "$USER_MANIFESTS" ]] && ls "$USER_MANIFESTS"/*.toml >/dev/null 2>&1; then
    # Generate user symlinks (append to link-spec or run directly)
    /usr/local/lib/containai/gen-user-links.sh "$USER_MANIFESTS"

    # Generate user launch wrappers (append to profile.d script)
    /usr/local/lib/containai/gen-user-wrappers.sh "$USER_MANIFESTS"
fi
```

3. Create lightweight runtime generators:
   - `gen-user-links.sh` - creates symlinks for user manifest entries
   - `gen-user-wrappers.sh` - appends functions to `/etc/profile.d/containai-user-agents.sh`

4. These use same parsing logic as build-time generators but run in container

## Flow

```
cai run (or cai run --fresh)
    │
    ├─> import (automatic)
    │     └─> syncs ~/.config/containai/manifests/ to volume
    │
    └─> container starts
          │
          └─> containai-init.sh (systemd oneshot)
                │
                ├─> built-in setup (existing)
                │
                └─> if user manifests exist:
                      ├─> gen-user-links.sh creates symlinks
                      └─> gen-user-wrappers.sh creates functions
                            │
                            ▼
                      myagent() wrapper available in shell
```

## Acceptance Criteria

- [ ] User manifest directory synced to container
- [ ] `containai-init.sh` checks for user manifests
- [ ] User symlinks created at startup
- [ ] User launch wrappers generated at startup
- [ ] Invalid user manifests logged, don't block startup
- [ ] Empty directory doesn't cause errors
- [ ] Works without container rebuild

## User Experience

```bash
# On host - create manifest once
cat > ~/.config/containai/manifests/myagent.toml << 'EOF'
[agent]
name = "myagent"
binary = "myagent"
default_args = ["--auto"]
optional = true

[[entries]]
source = ".myagent/config.json"
target = "myagent/config.json"
container_link = ".myagent/config.json"
flags = "fjo"
EOF

# Works on fresh container (cai run does import automatically)
cai run --fresh

# In container
myagent --help  # works with --auto prepended
ls ~/.myagent/  # symlink exists
```

No manual `cai import` needed - `cai run` handles it automatically.

## Notes

- Runtime generators are lightweight (bash, no Python)
- Reuse `parse-manifest.sh` logic
- User wrappers go to separate file to avoid clobbering built-in
