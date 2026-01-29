# fn-35-e0x Pi & Kimi Code Sync Support

## Overview

Add sync-manifest.toml entries for Pi coding agent (`@mariozechner/pi-coding-agent`) and Kimi CLI (`kimi-cli`) to enable config syncing between host and container.

**Note**: Both agents are already installed in the Docker image. This epic adds only the config sync support.

**Pi Agent**: `@mariozechner/pi-coding-agent` by Mario Zechner (badlogic). A coding agent CLI with read, bash, edit, write tools and session management. **NOT** Inflection AI's Pi.

**Kimi CLI**: MoonshotAI's official coding assistant CLI.

## Scope

### In Scope
- Add Pi entries to sync-manifest.toml
- Add Kimi entries to sync-manifest.toml
- Add data directories to Dockerfile.agents (mkdir -p)
- Run generators and rebuild image
- Verify sync works correctly

### Out of Scope
- Agent installation (already done)
- E2E tests (simple verification suffices)
- Documentation updates (separate epic)

## Approach

### Pi Config Locations (`~/.pi/agent/`)
| File | Purpose | Flags |
|------|---------|-------|
| `settings.json` | User preferences | `fj` |
| `models.json` | Provider config with API keys | `fjs` (SECRET) |
| `keybindings.json` | Key bindings | `fj` |
| `skills/` | Custom skills | `dR` |
| `extensions/` | Extensions | `dR` |
| `sessions/` | EXCLUDED - ephemeral, per-project |

### Kimi Config Locations (`~/.kimi/`)
| File | Purpose | Flags |
|------|---------|-------|
| `config.toml` | Main config with API keys | `fs` (SECRET) |
| `mcp.json` | MCP server config | `fjs` (SECRET) |
| `sessions/` | EXCLUDED - ephemeral |

### Dockerfile.agents Changes
Add to directory creation block (lines 51-59):
```dockerfile
/home/agent/.pi \
/home/agent/.pi/agent \
/home/agent/.kimi
```

## Tasks

### fn-35-e0x.1: Add Pi to sync-manifest.toml
Add entries for Pi config files. Use patterns from existing agents (Claude at lines 30-88).

### fn-35-e0x.2: Add Kimi to sync-manifest.toml
Add entries for Kimi config files. Similar pattern to Pi.

### fn-35-e0x.3: Add directories to Dockerfile.agents
Add mkdir -p for ~/.pi, ~/.pi/agent, ~/.kimi in the agent data directory block.

### fn-35-e0x.4: Run generators and rebuild
Run ./src/build.sh which regenerates symlinks.sh, init-dirs.sh, link-spec.json.

### fn-35-e0x.5: Verify sync works
Quick manual verification that configs sync correctly.

## Quick commands

```bash
# Build with new entries
./src/build.sh

# Test in container
cai shell
pi --version
kimi --version

# Verify symlinks exist
ls -la ~/.pi/agent/
ls -la ~/.kimi/

# Verify sync (if you have Pi/Kimi config)
cai import --dry-run | grep -E 'pi|kimi'
```

## Acceptance

- [ ] Pi entries added to sync-manifest.toml
- [ ] Kimi entries added to sync-manifest.toml
- [ ] Directories created in Dockerfile.agents
- [ ] Generated files updated (symlinks.sh, init-dirs.sh, link-spec.json)
- [ ] Image builds successfully
- [ ] Symlinks resolve correctly in container

## Dependencies

- **fn-36-rb7**: CLI UX Consistency (for container testing)

## References

- Pi Mono: https://github.com/badlogic/pi-mono
- Kimi CLI: https://github.com/MoonshotAI/kimi-cli
- Existing patterns: sync-manifest.toml lines 30-88 (Claude), 422-467 (Codex)
- Dockerfile.agents: src/container/Dockerfile.agents
