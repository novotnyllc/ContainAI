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
1. Installation in Dockerfile.agents
2. Config sync in sync-manifest.toml
3. Testing in container

## Step 1: Research the Agent

Before adding, understand:
- Installation method (npm, pip, curl, etc.)
- Configuration location (~/.config/agent/, ~/.agent/)
- Credential storage (files, env vars)
- Startup requirements

## Step 2: Add to Dockerfile.agents

Add installation after the SDK layers:

```dockerfile
# =============================================================================
# Agent Name
# =============================================================================
RUN <installation-command> \
    && agent --version || echo "[WARN] Agent installation failed"
```

Guidelines:
- Always verify installation with version check
- Use `|| echo "[WARN]"` to allow build to continue if install fails
- Group related commands with `&&`
- Document any special requirements

## Step 3: Add to sync-manifest.toml

Add entries for each config file/directory:

```toml
# =============================================================================
# AGENT NAME
# Description of what agent does
# =============================================================================

[[entries]]
source = ".agent/config.json"      # Path on host
target = "agent/config.json"       # Path in data volume
container_link = ".agent/config.json"  # Symlink in container home
flags = "fjo"                      # Flags (see below)
```

### Flags Reference

| Flag | Meaning |
|------|---------|
| f | File (not directory) |
| d | Directory |
| j | JSON init (create {} if empty) |
| s | Secret (skip with --no-secrets) |
| o | Optional (only sync if source exists on host) |
| m | Mirror mode (--delete removes extras) |
| x | Exclude .system/ subdirectory |
| R | Remove existing before symlink |
| g | Git filter (strip credential.helper) |

**IMPORTANT:** Use the `o` flag for all agent-specific entries. This prevents creating empty directories for agents the user doesn't have installed.

## Step 4: Generate Files

Run the generators:

```bash
./src/scripts/gen-dockerfile-symlinks.sh src/sync-manifest.toml src/container/generated/symlinks.sh
./src/scripts/gen-init-dirs.sh src/sync-manifest.toml src/container/generated/init-dirs.sh
./src/scripts/gen-container-link-spec.sh src/sync-manifest.toml src/container/generated/link-spec.json
```

## Step 5: Test

1. Build the image: `./src/build.sh`
2. Create a test container
3. Verify agent is installed: `ssh container 'agent --version'`
4. Import configs: `cai import`
5. Verify configs synced: `ssh container 'ls -la ~/.agent/'`
6. Verify no empty dirs for other agents: `ssh container 'ls -la ~/ | grep -v "^d.*agent"'`

## Examples

See existing agents in sync-manifest.toml:
- Claude Code: `.claude/`
- Codex: `.codex/`
- Gemini: `.gemini/`
- Pi: `.pi/`
```

## Tasks

### fn-38-8lv.1: Create adding-agents.md documentation
Comprehensive guide with examples from existing agents. Emphasize `o` flag usage.

### fn-38-8lv.2: Document agent config patterns
Add section on conventions (flag usage, path patterns, optional sync).

## Quick commands

```bash
# View existing agent patterns
grep -A5 "CLAUDE\|CODEX\|GEMINI\|PI" src/sync-manifest.toml

# View Dockerfile.agents patterns
cat src/container/Dockerfile.agents
```

## Acceptance

- [ ] `docs/adding-agents.md` created
- [ ] Documentation includes flag reference with emphasis on `o` flag
- [ ] Examples from Claude, Codex, Gemini, Pi included
- [ ] Generator commands documented
- [ ] Testing requirements documented

## Dependencies

- **fn-35-e0x**: Pi Support (provides another example agent)
- **fn-37-4xi**: Base Image Contract (referenced in docs)
- All other epics should be complete

## References

- Existing agents in sync-manifest.toml
- Dockerfile.agents: `src/container/Dockerfile.agents`
- Generator scripts: `src/scripts/gen-*.sh`
