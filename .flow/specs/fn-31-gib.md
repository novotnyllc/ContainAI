# fn-31-gib Import Reliability & Comprehensive Testing

## Overview

Fix critical import bugs and create a comprehensive E2E test suite for the import/sync functionality. Import is the heart of ContainAI's data management, and several bugs have been reported:

1. SSH keygen runs during import (caused by `eeacms/rsync` image entrypoint)
2. Codex skills not imported (missing symlinks) - needs crisp repro
3. Fresh container shows "claude: command not found"
4. Home directory pollution (empty .kiro, .cursor, etc. created for unused agents)
5. Likely other missing items in sync-manifest.toml

This epic also introduces `cai sync` - an in-container command for capturing installed tools to the data volume.

**Priority:** HIGH - User explicitly stated "Getting the import to work right is very important"

## Scope

### In Scope
- Investigate and fix SSH keygen running during `cai import` (rsync image entrypoint issue)
- Fix missing Codex skills import and symlink creation (with crisp repro)
- Audit sync-manifest.toml for completeness against currently supported agents
- Fix "claude: command not found" on fresh container start
- **Prevent home directory pollution** - implement `o` (optional) flag comprehensively
- **Add `cai sync` command** - in-container tool to move configs to data volume
- Install cai in container image (Dockerfile.agents) as real executable
- Create comprehensive import test suite (extending existing test infrastructure)
- **Test resources labeled with `containai.test=1`** for safe cleanup
- **Test volumes MUST start with `test-` prefix** (human safety net)
- **Test containers MUST start with `test-` prefix** (human safety net)
- Import filtering for `.priv.` files (from fn-12-css)

### Out of Scope
- New agent support (covered in fn-35-e0x) - this includes adding Kiro, Windsurf, Cline paths
- User templates (covered in fn-33-lp4)
- Changes to import UX (prompts, flags)

## Approach

### Phase 1: Bug Investigation

**SSH Keygen During Import**
- Root cause: `eeacms/rsync` image runs ssh-keygen in its entrypoint
- Current code runs `docker ... eeacms/rsync true` for mount preflight
- Tests filter "Generating SSH … ssh-keygen …" noise (`tests/integration/test-sync-integration.sh:run_in_rsync`)
- **Fix:** Override entrypoint with `--entrypoint rsync` or `--entrypoint sh -c 'true'`
- **Verify:** Tests should assert no ssh-keygen output (remove filter, expect clean output)

**Codex Skills Missing**
- Current state: `.codex/skills` exists in `src/sync-manifest.toml` with `flags = "dxR"`
- Symlinks generated in `src/container/generated/symlinks.sh`
- **Repro needed:** Define exact host layout that fails
- Bug could be in: (a) host→volume sync, (b) container symlink creation, (c) runtime link repair
- **Task:** Create minimal repro, then fix specific failure point

**Claude Not Found**
- `src/container/Dockerfile.agents` sets `ENV PATH="/home/agent/.local/bin:${PATH}"`
- Likely cause: how `cai shell` enters container (SSH vs exec) affects shell environment
- `.bashrc` vs `.profile` sourcing differs between login/interactive shells
- **Investigation:** Trace exact pathway `cai shell` uses and verify PATH in that context
- **Fix:** Ensure PATH is set in the right init file for SSH sessions

### Phase 2: Prevent Home Directory Pollution

**Problem:** Running `cai import` creates empty directories like `~/.kiro`, `~/.cursor`, etc. even if user doesn't use those agents.

**Root Cause Analysis:**
- Pollution comes from FOUR sources:
  1. `src/container/Dockerfile.agents` has `RUN mkdir -p /home/agent/.copilot .gemini .codex ...`
  2. `src/scripts/gen-init-dirs.sh` emits init steps for ALL manifest entries
  3. `src/scripts/gen-dockerfile-symlinks.sh` emits symlinks for ALL entries with `container_link`
  4. `src/scripts/gen-container-link-spec.sh` emits link repair specs for ALL entries

**Solution:** Add `o` (optional) flag with consistent behavior across ALL code paths:

| Flag `o` behavior | Dockerfile mkdir | Import | gen-init-dirs | gen-dockerfile-symlinks | gen-container-link-spec | cai sync |
|-------------------|------------------|--------|---------------|-------------------------|------------------------|----------|
| WITHOUT `o`       | Create dir | Always sync | Always init | Always symlink | Always repair | Process if has container_link |
| WITH `o`          | Skip mkdir | Only if host source exists | Skip init | Skip symlink | Skip repair | Process if has container_link |

**Note:** `cai sync` only processes entries that have `container_link` set (non-empty). Entries like `.gitconfig` with empty `container_link` are copy-only and not converted to symlinks.

**Implementation:**
1. Update `src/scripts/parse-manifest.sh` to expose `o` flag
2. Update `src/scripts/gen-init-dirs.sh` to skip `o` flagged entries
3. Update `src/scripts/gen-dockerfile-symlinks.sh` to skip `o` flagged entries
4. Update `src/scripts/gen-container-link-spec.sh` to skip `o` flagged entries
5. Update `src/container/Dockerfile.agents` to remove pre-creation of optional agent dirs
6. Update `src/lib/import.sh` to check source existence for `o` entries
7. Add `o` flag to agent-specific entries in `sync-manifest.toml` (existing agents only: Cursor, Aider, Continue, Copilot, Gemini)
8. Keep primary agents without `o` flag (`.claude`, `.codex`) - these are always available

**Existing agents in manifest that get `o` flag:**
- `.cursor` - optional
- `.continue` - optional
- `.aider` - optional
- `.copilot` - optional
- `.gemini` - optional

**Agents that do NOT get `o` flag (always available):**
- `.codex` - primary agent, commonly used
- `.claude` - primary agent, most common

### Phase 3: Import Filtering (from fn-12-css)

**Private file filtering:**
- Exclude `.bashrc.d/*.priv.*` files during import
- Prevents accidental secret leakage
- Controlled by `import.exclude_priv` config (default: true)

**Precedence rules:**
- `.priv.` exclusion is ALWAYS applied (security-critical)
- `--no-excludes` flag does NOT disable `.priv.` filtering
- Applies to both `--from <dir>` AND `--from <tgz>` restore
- Document: `.priv.` files must be manually copied if truly needed

### Phase 4: Audit sync-manifest.toml Completeness

**Problem:** Drift between manifest and code:
- `_IMPORT_SYNC_MAP` in `src/lib/import.sh` is separate from manifest
- Runtime init in `src/container/entrypoint.sh` has hardcoded paths

**Solution:**
1. Make `sync-manifest.toml` the authoritative source
2. Add CI check: `scripts/check-manifest-consistency.sh` that verifies:
   - `_IMPORT_SYNC_MAP` entries match manifest
   - Runtime init paths match manifest
3. Document which source is authoritative (manifest)

**Scope:** Audit covers currently supported agents only (Claude, Codex, Gemini, Cursor, Aider, Continue, Copilot). Adding new agents (Kiro, Windsurf, Cline) is out of scope (fn-35-e0x).

### Phase 5: `cai sync` Command (In-Container)

**Use Case:** User starts with clean image + clean data volume. They install agents, tools, customize their environment. Now they want that setup reusable across container recreations.

**Key insight:** Optional entries (`o` flag) start as real dirs/files in `$HOME`. `cai sync` moves them to `/mnt/agent-data` and creates symlinks.

**Scope limitation:** `cai sync` only processes manifest entries that have a non-empty `container_link` value. Entries like `.gitconfig` with empty `container_link` are copy-only and are NOT converted to symlinks by `cai sync`.

**Path semantics (critical for implementation):**
- `source` = path relative to `$HOME` containing user data (e.g., `.bash_aliases`)
- `target` = path on volume where data is stored (e.g., `bash/aliases`)
- `container_link` = symlink name in `$HOME` pointing to volume (e.g., `.bash_aliases_imported`)

**cai sync moves `source`, creates symlink at `container_link`:**
1. Move `$HOME/<source>` → `/mnt/agent-data/<target>`
2. Create symlink `$HOME/<container_link>` → `/mnt/agent-data/<target>`
3. If `container_link == source`, this is a simple move-and-symlink-in-place
4. If `container_link != source` (e.g., `.bash_aliases` → `.bash_aliases_imported`), both paths handled correctly

**Command:** Available as both:
- `/usr/local/bin/cai sync` (executable, works with `docker exec`)
- `cai sync` (sourced in interactive shell)

**Implementation:**
```bash
# /usr/local/bin/cai - executable wrapper
#!/bin/bash
source /opt/containai/containai.sh
cai "$@"
```

**What it does:**
1. Detect container environment (multiple signals required):
   - Check for `/mnt/agent-data` mountpoint (REQUIRED)
   - Check for `/.dockerenv` OR container cgroup markers (at least one REQUIRED)
   - Both conditions must pass
2. For each path in sync-manifest.toml WITH non-empty `container_link`:
   - Resolve realpath - reject if symlink in path
   - Verify resolved path would be under `/mnt/agent-data`
   - If path exists in home AND is not already a symlink to `/mnt/agent-data`:
     - Move to `/mnt/agent-data`
     - Replace with symlink
3. Report what was synced

**Security:**
- Container detection: `/mnt/agent-data` mountpoint AND (/.dockerenv OR cgroup marker)
- Symlink-attack prevention: reject paths containing symlinks, verify resolved paths
- Apply same validation as `containai-init.sh` (`verify_path_under_data_dir`, `reject_symlink`)

**Example:**
```bash
$ cai sync
[INFO] Syncing local configs to data volume...
[OK] ~/.claude -> /mnt/agent-data/claude (moved 3 files)
[OK] ~/.codex -> /mnt/agent-data/codex (moved 2 files)
[SKIP] ~/.gemini (already symlinked)
[INFO] Done. 2 paths synced, 1 skipped.
```

### Phase 6: Install cai in Container

Add cai to Dockerfile.agents as a real executable (not just sourced in .bashrc):

```dockerfile
# =============================================================================
# ContainAI CLI
# =============================================================================
COPY containai.sh /opt/containai/containai.sh
COPY lib/ /opt/containai/lib/

# Executable wrapper for non-interactive use
RUN printf '#!/bin/bash\nsource /opt/containai/containai.sh\ncai "$@"\n' > /usr/local/bin/cai && \
    chmod +x /usr/local/bin/cai

# Also source in .bashrc for interactive shells
RUN echo 'source /opt/containai/containai.sh' >> /home/agent/.bashrc
```

**Also:** Remove pre-creation of optional agent dirs from Dockerfile.agents (currently `RUN mkdir -p /home/agent/.copilot .gemini ...`). These will be created on-demand by import or `cai sync`.

**Verification:** `docker exec <container> cai --help` must work (non-interactive).

### Phase 7: Test Suite

**Approach:** Extend existing `tests/integration/test-sync-integration.sh` rather than duplicate. Add new scenarios to the existing framework.

```
tests/integration/
├── test-sync-integration.sh  # EXISTING - extended with new scenarios
├── lib/
│   └── sync-test-helpers.sh  # Common functions (may already exist)
└── fixtures/                  # Test fixtures (if not already present)
```

**Resource Identification (safety):**
- All test volumes: labeled `containai.test=1` + name starts with `test-`
- All test containers: labeled `containai.test=1` + name starts with `test-`
- Cleanup by label first, name prefix as human safety net

**Example:**
```bash
# Create test container with label
docker run --label containai.test=1 --name test-import-new-volume ...

# Cleanup by label (safe)
docker rm $(docker ps -aq --filter "label=containai.test=1")
docker volume rm $(docker volume ls -q --filter "label=containai.test=1")
```

**New Scenarios to Add:**
1. `test_new_volume` - fresh container + fresh volume + import
2. `test_existing_volume` - new container + existing data volume
3. `test_hot_reload` - running container + import
4. `test_no_pollution` - import with partial agent configs, verify no empty dirs
5. `test_cai_sync` - in-container cai sync
6. `test_no_ssh_keygen` - verify no ssh-keygen noise (remove filter, expect clean)
7. `test_priv_filtering` - verify `.priv.` files excluded

### Phase 8: CI Integration

**Tiered CI Strategy:**
1. **Standard runners (ubuntu-latest):**
   - Host-side import tests (rsync, manifest parsing)
   - shellcheck linting
   - Image builds
2. **Self-hosted runner (with sysbox):**
   - Full E2E with systemd containers
   - `cai sync` inside container
   - SSH session tests

**Implementation:**
```yaml
# .github/workflows/test.yml
jobs:
  lint-and-build:
    runs-on: ubuntu-latest
    # shellcheck, build images

  host-tests:
    runs-on: ubuntu-latest
    # Import parsing, manifest consistency

  e2e-tests:
    runs-on: self-hosted
    # requires: sysbox, docker
    # Full container lifecycle tests
```

## Tasks

### fn-31-gib.1: Fix SSH keygen noise during import
Override rsync image entrypoint to eliminate ssh-keygen noise.

### fn-31-gib.2: Fix missing Codex skills symlinks
Create minimal repro and fix specific failure point.

### fn-31-gib.3: Fix "claude: command not found" on fresh container
Investigate PATH in SSH session pathway.

### fn-31-gib.4: Audit sync-manifest.toml completeness
Verify manifest covers currently supported agents, add CI consistency check.

### fn-31-gib.5: Create import test infrastructure
Extend existing test framework with labeled resource helpers.

### fn-31-gib.6: Implement new-volume test scenario
Test fresh container + fresh volume + import.

### fn-31-gib.7: Implement existing-volume test scenario
Test new container attaching to existing data volume.

### fn-31-gib.8: Implement hot-reload test scenario
Test running container + import (live reload).

### fn-31-gib.9: Implement data-migration test scenario
Test volume with user modifications survives container recreation.

### fn-31-gib.10: Integrate tests into CI
Add import tests to GitHub Actions with tiered strategy.

### fn-31-gib.11: Prevent home directory pollution
Implement `o` (optional) flag across all code paths including Dockerfile.

### fn-31-gib.12: Install cai in container image
Add cai CLI to Dockerfile.agents as real executable.

### fn-31-gib.13: Implement cai sync command
In-container command to move configs to data volume with symlinks.

### fn-31-gib.14: Implement no-pollution test scenario
Test import with partial agent configs creates no empty directories.

### fn-31-gib.15: Implement cai sync test scenario
Test in-container cai sync moves files and creates symlinks.

### fn-31-gib.16: Add .priv. file filtering to import
Exclude `.bashrc.d/*.priv.*` files during import.

## Quick commands

```bash
# Build image if needed
./src/build.sh

# Run import manually for debugging
source src/containai.sh
cai import --dry-run

# Check sync-manifest.toml
cat src/sync-manifest.toml | grep -A3 codex

# List test resources (by label - preferred)
docker ps -a --filter "label=containai.test=1"
docker volume ls --filter "label=containai.test=1"

# Clean up ALL test resources (by label)
docker stop $(docker ps -q --filter "label=containai.test=1") 2>/dev/null || true
docker rm $(docker ps -aq --filter "label=containai.test=1") 2>/dev/null || true
docker volume rm $(docker volume ls -q --filter "label=containai.test=1") 2>/dev/null || true
```

## Acceptance

- [ ] `cai import` does NOT produce ssh-keygen noise
- [ ] Codex skills (`.codex/skills`) are imported and symlinked correctly
- [ ] Fresh container has working `claude` command via `cai shell`
- [ ] sync-manifest.toml covers all currently supported agent config paths
- [ ] CI checks manifest/import-map consistency
- [ ] Import does NOT create empty dirs for agents user doesn't have (`o` flag works)
- [ ] Dockerfile.agents does NOT pre-create optional agent dirs
- [ ] `.bashrc.d/*.priv.*` files are NOT imported (even with `--no-excludes`)
- [ ] `cai sync` works inside container (non-interactive and interactive)
- [ ] `cai sync` only processes entries with `container_link`
- [ ] `cai sync` refuses to run on host (multiple signal detection)
- [ ] cai installed in container image as executable (`/usr/local/bin/cai`)
- [ ] Test suite covers all scenarios with labeled resources
- [ ] CI runs import tests on PR (tiered: host tests always, E2E on self-hosted)

## Dependencies

- **fn-36-rb7**: CLI UX consistency provides workspace state, better container naming
- **fn-41-9xt**: Plugin architecture (if cai sync uses plugins)
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
- Init dirs generation: `src/scripts/gen-init-dirs.sh`
- Link spec generation: `src/scripts/gen-container-link-spec.sh`
- Manifest parser: `src/scripts/parse-manifest.sh`
- Dockerfile: `src/container/Dockerfile.agents`
