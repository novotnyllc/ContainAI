# fn-38-8lv Agent Addition Documentation

## Overview

Create comprehensive documentation for adding new AI agents to ContainAI. This helps contributors and advanced users understand the process.

**Priority:** LAST - After all other epics, including fn-37-4xi (Base Image Contract).

## Scope

### In Scope
- Create `docs/adding-agents.md`
- Document sync-manifest.toml flags and patterns
- Document Dockerfile.agents conventions
- Document testing requirements
- Include examples from existing agents (Claude, Codex, Gemini, Pi)

### Out of Scope
- Agent marketplace/registry
- Automated agent discovery
- User-creatable agents (they use templates instead)

## Approach

### Agent Addition Documentation

Create `docs/adding-agents.md`:

```markdown
# Adding a New Agent to ContainAI

This guide explains how to add support for a new AI coding agent.

## Overview

Adding an agent involves:
1. Research the agent
2. Add installation in Dockerfile.agents
3. Add config entries in sync-manifest.toml
4. Update _IMPORT_SYNC_MAP in import.sh
5. Run generators and consistency check
6. Test in container

## Step 1: Research the Agent

Before adding, understand:
- Installation method (npm, pip, curl, etc.)
- Configuration location (~/.config/agent/, ~/.agent/)
- Credential storage (files, env vars)
- Startup requirements

## Step 2: Add to Dockerfile.agents

Add installation after the SDK layers:

### Required agents (fail-fast)

For agents that must be present in the image:

```dockerfile
# =============================================================================
# Agent Name
# =============================================================================
RUN <installation-command> \
    && agent --version
```

### Optional components (soft-fail)

For truly optional components where absence is acceptable:

```dockerfile
# Optional: Agent Name (soft-fail if unavailable)
RUN ( <installation-command> && agent --version ) \
    || echo "[WARN] Agent installation failed - continuing without it"
```

Guidelines:
- **Required agents**: fail-fast with `&& agent --version` - keeps image trustworthy
- **Optional components**: use explicit grouping `( cmd ) || warn` with clear justification
- Group related commands with `&&`
- Document any special requirements in comments

## Step 3: Add to sync-manifest.toml

Add entries for each config file/directory:

```toml
# =============================================================================
# AGENT NAME
# Description of what agent does
# =============================================================================

[[entries]]
source = ".agent/config.json"      # Path on host (relative to $HOME)
target = "agent/config.json"       # Path in data volume (/mnt/agent-data)
container_link = ".agent/config.json"  # Symlink in container home
flags = "fjos"                     # Flags (see below)
```

### Flags Reference

| Flag | Meaning |
|------|---------|
| f | File (not directory) |
| d | Directory |
| j | JSON init (create {} if empty) |
| s | Secret (600 for files, 700 for dirs; skipped with --no-secrets) |
| o | Optional (skip if source doesn't exist; don't pre-create in Dockerfile/init) |
| m | Mirror mode (--delete removes extras) |
| x | Exclude .system/ subdirectory |
| R | Remove existing path first (rm -rf before ln -sfn) |
| g | Git filter (strip credential.helper and signing config) |
| G | Glob/dynamic pattern (discovered at runtime, not synced directly) |

### Optional vs Required Agents

- **Required/primary agents** (e.g., Claude, Codex): Omit `o` flag - these are always synced
- **Optional agents** (e.g., Copilot, Gemini, Pi, Kimi): Use `o` flag to avoid creating empty directories for agents the user doesn't have installed

Example of optional agent entry:
```toml
[[entries]]
source = ".gemini/settings.json"
target = "gemini/settings.json"
container_link = ".gemini/settings.json"
flags = "fjso"  # includes o = optional
```

### Container-Only Symlinks

For entries that exist only in the container (not imported from host):

```toml
[[container_symlinks]]
target = "some/path/file.json"       # Path in volume
container_link = ".config/file.json"  # Symlink in container home
flags = "fj"                          # flags for structure
```

### Disabled Entries

For entries that should generate symlinks/init but not be synced by default:

```toml
[[entries]]
source = ".agent/config"
target = "agent/config"
container_link = ".agent/config"
flags = "ds"
disabled = true  # Excluded from _IMPORT_SYNC_MAP; use additional_paths if needed
```

## Step 4: Update _IMPORT_SYNC_MAP

After modifying sync-manifest.toml, update the corresponding import map:

1. Edit `src/lib/import.sh` - update `_IMPORT_SYNC_MAP` array
2. Run the consistency check:
   ```bash
   ./scripts/check-manifest-consistency.sh
   ```
3. CI enforces this alignment - builds will fail if manifest and import map diverge

## Step 5: Run Generators

The generators create container artifacts from the manifest:

```bash
./src/scripts/gen-dockerfile-symlinks.sh src/sync-manifest.toml src/container/generated/symlinks.sh
./src/scripts/gen-init-dirs.sh src/sync-manifest.toml src/container/generated/init-dirs.sh
./src/scripts/gen-container-link-spec.sh src/sync-manifest.toml src/container/generated/link-spec.json
```

**Note:** Building with `./src/build.sh` runs these generators automatically.

## Step 6: Test

Testing follows the tiered strategy in `docs/testing.md`:

### Tier 1: Linting (host-side)
```bash
# Shell script linting
shellcheck -x src/*.sh src/lib/*.sh

# Manifest consistency
./scripts/check-manifest-consistency.sh
```

### Tier 2: Integration Tests
```bash
# Run sync integration tests
./tests/integration/test-sync-integration.sh
```

### Tier 3: E2E Tests (requires sysbox + container)

1. Start container:
   ```bash
   # On host
   ./src/build.sh                    # Build image
   cai run --container test-agent    # Creates container + configures SSH
   ```

2. Verify agent installed (from host, via SSH):
   ```bash
   # Replace 'newagent' with actual agent binary name
   ssh test-agent 'newagent --version'
   ```

3. Import configs (from host):
   ```bash
   cai import
   ```

4. Verify configs synced (from host, via SSH):
   ```bash
   # Replace .newagent with actual agent config directory
   ssh test-agent 'ls -la ~/.newagent/'
   ```

5. Verify no empty dirs for optional agents (from host, via SSH):
   ```bash
   # Check specific optional agent directories
   ssh test-agent 'for d in .copilot .gemini .pi .kimi; do [ -d ~/"$d" ] && echo "WARNING: $d exists unexpectedly"; done'
   ```

## Examples

See existing agent patterns in sync-manifest.toml:

### Required Agents (no `o` flag)
- **Claude Code**: `.claude/`, `.claude.json` - primary supported agent
- **Codex**: `.codex/` - primary supported agent

### Optional Agents (with `o` flag)
- **Gemini**: `.gemini/` - optional
- **Pi**: `.pi/` - optional
- **Copilot**: `.copilot/` - optional
- **Kimi**: `.kimi/` - optional
```

## Tasks

### fn-38-8lv.1: Create adding-agents.md documentation
Comprehensive guide with examples from existing agents. Cover required vs optional agent patterns.

### fn-38-8lv.2: Document agent config patterns
Add section on conventions (flag usage, path patterns, _IMPORT_SYNC_MAP requirements).

## Quick commands

```bash
# View existing agent patterns (using rg for POSIX portability)
rg -A5 'CLAUDE|CODEX|GEMINI|PI\b|COPILOT|KIMI' src/sync-manifest.toml

# View Dockerfile.agents patterns
cat src/container/Dockerfile.agents

# Check manifest/import map consistency
./scripts/check-manifest-consistency.sh
```

## Acceptance

- [ ] `docs/adding-agents.md` created
- [ ] Documentation includes complete flag reference (f, d, j, s, o, m, x, R, g, G)
- [ ] Required vs optional agent patterns documented with `o` flag guidance
- [ ] `_IMPORT_SYNC_MAP` update + consistency check workflow documented
- [ ] `container_symlinks` and `disabled` fields documented
- [ ] Generator commands documented
- [ ] Testing requirements documented (referencing docs/testing.md tiers)
- [ ] Examples from Claude, Codex, Gemini, Pi included
- [ ] Host vs container command distinction clear in testing steps

## Dependencies

- **fn-35-e0x**: Pi Support (provides another example agent)
- **fn-37-4xi**: Base Image Contract (referenced in docs)
- All other epics should be complete

## References

- Existing agents in sync-manifest.toml
- Dockerfile.agents: `src/container/Dockerfile.agents`
- Generator scripts: `src/scripts/gen-*.sh`
- Testing guide: `docs/testing.md`
- Manifest consistency: `scripts/check-manifest-consistency.sh`
