# fn-31-gib Import Reliability & Comprehensive Testing

## Overview

Fix critical import bugs and create a comprehensive E2E test suite for the import/sync functionality. Import is the heart of ContainAI's data management, and several bugs have been reported:

1. SSH keygen runs during import (shouldn't happen)
2. Codex skills not imported (missing symlinks)
3. Fresh container shows "claude: command not found"
4. Home directory pollution (empty .kiro, .cursor, etc. created for unused agents)
5. Likely other missing items in sync-manifest.toml

This epic also introduces `cai sync` - an in-container command for capturing installed tools to the data volume.

**Priority:** HIGH - User explicitly stated "Getting the import to work right is very important"

## Scope

### In Scope
- Investigate and fix SSH keygen running during `cai import`
- Fix missing Codex skills import and symlink creation
- Audit sync-manifest.toml for completeness against all supported agents
- Fix "claude: command not found" on fresh container start
- **Prevent home directory pollution** - don't create empty dirs for agents user doesn't have
- **Add `cai sync` command** - in-container tool to move configs to data volume
- Install cai in container image (Dockerfile.agents)
- Create comprehensive import test suite
- **Test volumes MUST start with `test-` prefix**
- **Test containers MUST start with `test-` prefix** (always specify --container test-xxx)
- Import filtering for `.priv.` files (from fn-12-css)

### Out of Scope
- New agent support (covered in fn-35-e0x)
- User templates (covered in fn-33-lp4)
- Changes to import UX (prompts, flags)

## Approach

### Phase 1: Bug Investigation

**SSH Keygen During Import**
- Trace `cai import` code path in `src/lib/import.sh`
- Identify where `_cai_ensure_ssh_key` or similar is called
- SSH keys should only be generated for container creation, not import

**Codex Skills Missing**
- Check sync-manifest.toml entry for `.codex/skills`
- Verify `flags = "dxR"` (directory, exclude .system/, remove existing)
- Check if symlink is being created in container
- Test with actual Codex installation

**Claude Not Found**
- Fresh container means new volume + new container
- Check if `containai-init.sh` runs correctly
- Verify PATH includes `/home/agent/.local/bin` where claude is installed
- Check if symlinks from volume to home are created

### Phase 2: Prevent Home Directory Pollution

**Problem:** Running `cai import` creates empty directories like `~/.kiro`, `~/.cursor`, etc. even if user doesn't use those agents. This clutters the home directory.

**Solution:** Only sync/create symlinks for paths that **exist on the host**.

Current behavior:
```bash
# Creates ~/.kiro even if user has no kiro config
mkdir -p /mnt/agent-data/kiro
ln -sfn /mnt/agent-data/kiro ~/.kiro
```

New behavior:
```bash
# Only create if source exists on host
if [[ -e "$HOME/.kiro" ]]; then
    # sync and symlink
fi
```

**Implementation:**
1. Modify import logic to check source existence before syncing
2. Modify symlink generation to be conditional
3. Add flag `o` (optional) to sync-manifest entries that should only sync if present
4. Entries without `o` flag are always synced (required dirs like `.config/containai`)

### Phase 3: Import Filtering (from fn-12-css)

**Private file filtering:**
- Exclude `.bashrc.d/*.priv.*` files during import
- Prevents accidental secret leakage
- Controlled by `import.exclude_priv` config (default: true)

### Phase 4: `cai sync` Command (In-Container)

**Use Case:** User starts with clean image + clean data volume. They install agents, tools, customize their environment. Now they want that setup reusable across container recreations.

**Command:**
```bash
# Inside container
cai sync
```

**What it does:**
1. Detects it's running inside a container (check for `/mnt/agent-data`)
2. For each path in sync-manifest.toml:
   - If path exists in home AND is not already a symlink to /mnt/agent-data
   - Move the path to /mnt/agent-data
   - Replace with symlink back
3. Reports what was synced

**Safety:**
- MUST detect container environment - refuse to run on host
- Detection: check for `/mnt/agent-data` mount point or container label
- Never move/replace files on the actual host machine

**Example:**
```bash
$ cai sync
[INFO] Syncing local configs to data volume...
[OK] ~/.claude -> /mnt/agent-data/claude (moved 3 files)
[OK] ~/.codex -> /mnt/agent-data/codex (moved 2 files)
[SKIP] ~/.gemini (already symlinked)
[INFO] Done. 2 paths synced, 1 skipped.
```

### Phase 5: Install cai in Container

Add cai to Dockerfile.agents so `cai sync` works inside container:
```dockerfile
# =============================================================================
# ContainAI CLI
# =============================================================================
COPY containai.sh /opt/containai/containai.sh
COPY lib/ /opt/containai/lib/
RUN echo 'source /opt/containai/containai.sh' >> /home/agent/.bashrc
```

### Phase 6: Test Suite

```
tests/integration/import/
├── run-import-tests.sh       # Main test runner
├── lib/
│   ├── test-helpers.sh       # Common functions
│   ├── fixtures.sh           # Test fixture creation
│   └── cleanup.sh            # Container/volume cleanup
├── fixtures/
│   ├── claude-config/        # Expected Claude files
│   ├── codex-config/         # Expected Codex files
│   └── ...
└── scenarios/
    ├── test-new-volume.sh    # New container + new volume
    ├── test-existing-volume.sh  # New container + existing volume
    ├── test-hot-reload.sh    # Running container + import
    ├── test-data-migration.sh   # Volume with modifications
    ├── test-no-pollution.sh  # Verify no empty dirs created
    └── test-cai-sync.sh      # Test in-container sync
```

**CRITICAL: Test Resource Naming**
- All test volumes MUST start with `test-` prefix
- All test containers MUST start with `test-` prefix
- Always specify `--container test-xxx` when creating test containers via cai commands
- This prevents accidental clobbering of user files/containers

**Example test container creation:**
```bash
# CORRECT - explicit test-prefixed container name
cai shell --container test-import-new-volume --data-volume test-import-001

# WRONG - no container name, might clobber user's container
cai shell --data-volume test-import-001
```

**Cleanup Strategy:**
- Stop containers: `docker stop $(docker ps -q --filter "name=^test-")`
- Remove containers: `docker rm $(docker ps -aq --filter "name=^test-")`
- Remove volumes: `docker volume rm $(docker volume ls -q --filter "name=^test-")`
- Never touch non-test resources

## Tasks

### fn-31-gib.1: Investigate SSH keygen during import
Trace the import code path and identify why SSH key generation is triggered during `cai import`. Fix the issue so import only syncs config files without side effects.

### fn-31-gib.2: Fix missing Codex skills and symlinks
Debug why `.codex/skills` (and potentially other directories) aren't being imported or symlinked correctly. Verify sync-manifest.toml entry and symlink generation.

### fn-31-gib.3: Fix "claude: command not found" on fresh container
Investigate why Claude CLI is not available on fresh container start. Check PATH, symlinks, and containai-init.sh execution.

### fn-31-gib.4: Audit sync-manifest.toml completeness
Review each supported agent against their actual config structure. Add missing entries, fix incorrect paths/flags.

### fn-31-gib.5: Prevent home directory pollution
Modify import to only sync/symlink paths that exist on host. Add optional flag `o` to sync-manifest.toml entries.

### fn-31-gib.6: Add .priv. file filtering to import
Exclude `.bashrc.d/*.priv.*` files during import. Add config option `import.exclude_priv` (default: true).

### fn-31-gib.7: Install cai in container image
Add cai CLI to Dockerfile.agents. Ensure it's sourced in .bashrc.

### fn-31-gib.8: Implement cai sync command
In-container command to move local configs to data volume and replace with symlinks. Include safety checks to prevent running on host.

### fn-31-gib.9: Create import test infrastructure
Build test framework with helpers, fixtures, and cleanup functions. Ensure all test containers use `test-` prefix.

### fn-31-gib.10: Implement new-volume test scenario
Test: fresh container + fresh volume + import. Use `--container test-new-volume`.

### fn-31-gib.11: Implement existing-volume test scenario
Test: new container + existing data volume. Use `--container test-existing-volume`.

### fn-31-gib.12: Implement hot-reload test scenario
Test: running container + import. Use `--container test-hot-reload`.

### fn-31-gib.13: Implement no-pollution test scenario
Test: import with partial agent configs. Verify no empty dirs created.

### fn-31-gib.14: Implement cai sync test scenario
Test: in-container cai sync. Verify files moved and symlinked correctly.

### fn-31-gib.15: Integrate tests into CI
Add import tests to GitHub Actions workflow. Ensure tests run on PR.

## Quick commands

```bash
# Build image if needed
./src/build.sh

# Run import manually for debugging
source src/containai.sh
cai import --dry-run

# Check sync-manifest.toml
cat src/sync-manifest.toml | grep -A3 codex

# List test resources
docker ps -a --filter "name=^test-"
docker volume ls --filter "name=^test-"

# Test cai sync inside container
cai shell --container test-sync-manual
cai sync --dry-run

# Clean up ALL test resources
docker stop $(docker ps -q --filter "name=^test-") 2>/dev/null || true
docker rm $(docker ps -aq --filter "name=^test-") 2>/dev/null || true
docker volume rm $(docker volume ls -q --filter "name=^test-") 2>/dev/null || true
```

## Acceptance

- [ ] `cai import` does NOT trigger SSH keygen
- [ ] Codex skills (`.codex/skills`) are imported and symlinked correctly
- [ ] Fresh container has working `claude` command
- [ ] sync-manifest.toml covers all supported agent config paths
- [ ] Import does NOT create empty dirs for agents user doesn't have
- [ ] `.bashrc.d/*.priv.*` files are NOT imported
- [ ] `cai sync` works inside container
- [ ] `cai sync` refuses to run on host (safety check)
- [ ] cai installed in container image
- [ ] Test suite covers all scenarios
- [ ] All test volumes use `test-` prefix
- [ ] All test containers use `test-` prefix
- [ ] CI runs import tests on PR

## Dependencies

- **fn-36-rb7**: CLI UX consistency provides workspace state, better container naming
- **fn-35-e0x**: Pi support establishes agent addition pattern
- **fn-10-vep** (complete): Sysbox system container infrastructure
- **fn-17-axl** (complete): Config Sync v2 architecture

## Supersedes

- **fn-12-css** import filtering tasks (`.priv.` file exclusion)

## References

- Import implementation: `src/lib/import.sh`
- Sync manifest: `src/sync-manifest.toml`
- Container init: `src/container/containai-init.sh`
- Existing sync tests: `tests/integration/test-sync-integration.sh`
- Symlink generation: `src/scripts/gen-dockerfile-symlinks.sh`
