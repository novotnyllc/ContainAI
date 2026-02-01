# fn-35-e0x.5 Build and verify

## Description
Run build script, verify consistency check passes, and smoke test in container.

**Size:** S
**Files:** None (verification only)

## Approach

1. Run consistency check:
```bash
scripts/check-manifest-consistency.sh
```

2. Run build:
```bash
./src/build.sh
```

3. Smoke test in container:
```bash
cai shell
pi --version
kimi --version
```

4. Verify optional sync behavior inside container:
```bash
# Enter container
cai shell

# Create mock Pi config under $HOME (cai sync moves from $HOME to data volume)
mkdir -p ~/.pi/agent
echo '{}' > ~/.pi/agent/settings.json

# Run cai sync to move config to data volume and create symlink
cai sync

# Verify symlink created and points to data volume
readlink ~/.pi/agent/settings.json
# Should output: /mnt/agent-data/pi/settings.json

# Verify config was moved to data volume
cat /mnt/agent-data/pi/settings.json
# Should output: {}
```

## Key context

- build.sh auto-runs all generators
- **Optional entries (`o` flag) are NOT in generated files** - this is by design
- Symlinks for optional agents are created dynamically by `cai sync` when user has config
- Agents should work (installed in image, config comes later via sync)

## Acceptance
- [ ] `scripts/check-manifest-consistency.sh` passes
- [ ] Docker image builds without errors
- [ ] pi --version works in container
- [ ] kimi --version works in container
- [ ] `cai sync` creates symlinks when Pi/Kimi configs exist under `$HOME`

## Done summary
# fn-35-e0x.5 Build and Verify Summary

## Verification Results

### 1. Consistency Check
- Command: `scripts/check-manifest-consistency.sh`
- Result: **PASS** - 70 entries checked, manifest and import map are consistent

### 2. Docker Image Build
- Command: `./src/build.sh`
- Result: **PASS** - All layers built successfully
  - containai/base
  - containai/sdks
  - containai/agents
  - containai/full
  - containai (final)

### 3. Pi Agent Version Check
- Command: `docker run --entrypoint /bin/bash containai:latest -c "pi --version"`
- Result: **PASS** - `0.50.9`

### 4. Kimi Agent Version Check
- Command: `docker run --entrypoint /bin/bash containai:latest -c "kimi --version"`
- Result: **PASS** - `kimi, version 1.5`

### 5. cai sync Optional Behavior
- **LIMITATION**: Cannot test in this environment
- Reason: Nested Docker environment lacks sysbox runtime required for systemd containers
- The sync functionality relies on systemd services running in the container
- However, manifest entries are correctly configured (verified by consistency check)
- Pi entries: settings.json, models.json, keybindings.json, skills/, extensions/ (all with `o` flag)
- Kimi entries: config.toml, mcp.json (all with `o` flag)

## Files Verified
- `src/sync-manifest.toml`: Pi entries at lines 554-580, Kimi entries at lines 590-598
- `src/lib/import.sh`: Pi entries at lines 495-499, Kimi entries at lines 503-504

## Environment Limitations
This verification ran in a nested sysbox container without access to sysbox runtime, preventing full `cai sync` testing. The container-based agent verification (pi/kimi --version) was successful using entrypoint override.
## Evidence
- Commits:
- Tests:
- PRs:
