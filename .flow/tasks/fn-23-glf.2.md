# fn-23-glf.2 Fix symlinks.sh build failure in docker.yml workflow

## Description

The buildx build fails during the symlinks.sh execution:

```
ERROR: failed to build: failed to solve: process "/bin/bash -o pipefail -c chmod +x /tmp/symlinks.sh && /tmp/symlinks.sh && rm /tmp/symlinks.sh" did not complete successfully: exit code: 1
```

### Root cause analysis

The failure is silent - `set -e` in symlinks.sh causes exit on first error but doesn't show which command failed.

Potential causes:
1. **GHA cache staleness** - The cache (`cache-from: type=gha,scope=full`) may serve old layers from before the `/mnt/agent-data` permission fix
2. **Generated file drift** - `docker.yml` doesn't run generators, relies on committed files which may be stale
3. **Buildx layer isolation** - Multi-platform buildx may not properly inherit `/mnt/agent-data` permissions from previous RUN

### Solution

1. **Run generators in CI** - Add a step to `docker.yml` to regenerate files before building
2. **Add verbose error handling to symlinks.sh** - Replace `set -e` with explicit error checking so failures show context
3. **Bust the GHA cache** - Change cache scope or add a comment to invalidate stale layers

### Files to modify

- `.github/workflows/docker.yml` - Add generator step before builds
- `src/container/generated/symlinks.sh` - Add error reporting (regenerate via generator)
- `src/scripts/gen-dockerfile-symlinks.sh` - Update template to include better error handling

### Detailed changes

**docker.yml**: Add step before "Build and push full image":
```yaml
- name: Generate container files
  run: |
    ./src/scripts/gen-dockerfile-symlinks.sh src/sync-manifest.toml src/container/generated/symlinks.sh
    ./src/scripts/gen-init-dirs.sh src/sync-manifest.toml src/container/generated/init-dirs.sh
    ./src/scripts/gen-container-link-spec.sh src/sync-manifest.toml src/container/generated/link-spec.json
    cp src/container/link-repair.sh src/container/generated/link-repair.sh
```

**symlinks.sh** (via generator): Add error context:
```sh
#!/bin/sh
# Generated from sync-manifest.toml - DO NOT EDIT
set -e

# Error handler to show which command failed
trap 'echo "ERROR: Command failed at line $LINENO" >&2' ERR

# Verify /mnt/agent-data is writable
if ! touch /mnt/agent-data/.write-test 2>/dev/null; then
    echo "ERROR: /mnt/agent-data is not writable by $(whoami)" >&2
    ls -la /mnt/agent-data 2>&1 || echo "/mnt/agent-data does not exist" >&2
    exit 1
fi
rm -f /mnt/agent-data/.write-test

mkdir -p \
    ...
```

## Acceptance

- [ ] `docker.yml` runs generators before building agents layer
- [ ] symlinks.sh includes error context on failure
- [ ] Build passes for both amd64 and arm64 platforms
- [ ] No reliance on committed generated files for CI builds

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
