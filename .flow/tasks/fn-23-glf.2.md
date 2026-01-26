# fn-23-glf.2 Fix symlinks.sh build failure in docker.yml workflow

## Description

The buildx build fails during the symlinks.sh execution:

```
ERROR: failed to build: failed to solve: process "/bin/bash -o pipefail -c chmod +x /tmp/symlinks.sh && /tmp/symlinks.sh && rm /tmp/symlinks.sh" did not complete successfully: exit code: 1
```

### Root cause analysis

The failure is silent - `set -e` in symlinks.sh causes exit on first error but doesn't show which command failed. The failure is likely deterministic (link collision or permission issue), not cache-related.

Potential causes:
1. **Link collision** - attempting to create symlink where a file/directory already exists
2. **Permission issue** - `/mnt/agent-data` not writable or ownership mismatch
3. **Path doesn't exist** - parent directory for symlink target missing

### Solution

1. **Primary: Add deterministic logging to symlinks.sh**
   - Convert from `#!/bin/sh` to `#!/usr/bin/env bash` (enables proper error handling)
   - Update Dockerfile.agents to run with `bash` instead of relying on shebang
   - Log each command before execution
   - On failure, show: failing command, `id`, `ls -ld /mnt/agent-data`, and `ls -ld` of the failing path

2. **Run generators in CI** - Add a step to `docker.yml` to regenerate files before building

3. **Secondary: Bust GHA cache** - Change cache scope from `full` → `full-v2` (one-time)

### Files to modify

- `src/scripts/gen-dockerfile-symlinks.sh` - Update template to generate bash script with logging
- `src/container/Dockerfile.agents` - Update RUN command to use bash explicitly
- `.github/workflows/docker.yml` - Add generator step, change cache scope to `full-v2`

### Detailed changes

**gen-dockerfile-symlinks.sh**: Update template to generate:
```bash
#!/usr/bin/env bash
# Generated from sync-manifest.toml - DO NOT EDIT
# Regenerate with: src/scripts/gen-dockerfile-symlinks.sh
set -euo pipefail

# Logging helper - prints command and executes it
run_cmd() {
    echo "+ $*"
    if ! "$@"; then
        echo "ERROR: Command failed: $*" >&2
        echo "  id: $(id)" >&2
        echo "  ls -ld /mnt/agent-data:" >&2
        ls -ld /mnt/agent-data 2>&1 | sed 's/^/    /' >&2 || echo "    (not found)" >&2
        exit 1
    fi
}

# Verify /mnt/agent-data is writable
if ! touch /mnt/agent-data/.write-test 2>/dev/null; then
    echo "ERROR: /mnt/agent-data is not writable by $(id)" >&2
    ls -la /mnt/agent-data 2>&1 || echo "/mnt/agent-data does not exist" >&2
    exit 1
fi
rm -f /mnt/agent-data/.write-test

run_cmd mkdir -p \
    ...

run_cmd ln -sfn ...
```

**Dockerfile.agents**: Change from:
```dockerfile
RUN chmod +x /tmp/symlinks.sh && /tmp/symlinks.sh && rm /tmp/symlinks.sh
```
to:
```dockerfile
RUN bash /tmp/symlinks.sh && rm /tmp/symlinks.sh
```

**docker.yml**: Add before "Build and push full image":
```yaml
- name: Generate container files
  run: |
    ./src/scripts/gen-dockerfile-symlinks.sh src/sync-manifest.toml src/container/generated/symlinks.sh
    ./src/scripts/gen-init-dirs.sh src/sync-manifest.toml src/container/generated/init-dirs.sh
    ./src/scripts/gen-container-link-spec.sh src/sync-manifest.toml src/container/generated/link-spec.json
    cp src/container/link-repair.sh src/container/generated/link-repair.sh
```

And change cache scopes from `full` to `full-v2`.

## Acceptance

- [ ] `docker.yml` runs generators before building agents layer
- [ ] symlinks.sh uses bash (`#!/usr/bin/env bash`) not sh
- [ ] symlinks.sh logs each command before execution (via `run_cmd` wrapper)
- [ ] On failure, symlinks.sh shows failing command, `id`, and `ls -ld` of relevant paths
- [ ] Dockerfile.agents runs symlinks.sh with `bash` explicitly
- [ ] Cache scope changed from `full` to `full-v2`
- [ ] Build passes for both amd64 and arm64 platforms
- [ ] CI regenerates and uses generated files (doesn't require them to be up-to-date in git)

## Done summary
Added deterministic logging to symlinks.sh for debugging build failures: converted from sh to bash with run_cmd wrapper that logs each command before execution and shows id, ls -ld /mnt/agent-data, and ls -ld of all failing path arguments on failure. Updated docker.yml to regenerate container files before building and changed cache scope to full-v2 to bust stale cache.
## Evidence
- Commits: ddc8a249ba7abe0db36807dfc84f87db2bc9ef5f, 950f4ed5c4efb6ec059a10f326a6a8f9e8fdb9d9, 4c3dc3a327a911be96bbfcc5c1bc661b4d57c8f7
- Tests: shellcheck src/scripts/gen-dockerfile-symlinks.sh, shellcheck src/container/generated/symlinks.sh
- PRs:
