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
- Update `_IMPORT_SYNC_MAP` in `src/lib/import.sh` (required for consistency)
- Run generators and rebuild image
- Verify sync works correctly

### Out of Scope
- Agent installation (already done)
- Comprehensive E2E tests (smoke verification only)
- Documentation updates (separate epic)
- Pre-creating directories in Dockerfile (Pi/Kimi are optional agents)

## Approach

### Architecture Decision: Optional Agents

Pi and Kimi are treated as **optional agents** (like Copilot, Gemini, Aider), not primary agents (like Claude, Codex). This means:
- Directories are NOT pre-created in Dockerfile.agents to prevent home pollution
- Entries use `o` flag (optional) so symlinks are created only when user has config
- Users who configure these agents inside the container should run `cai sync` to persist

This aligns with the existing policy in `Dockerfile.agents:51-56`.

### Pi Config Locations (`~/.pi/agent/`)
| File | Purpose | Flags |
|------|---------|-------|
| `settings.json` | User preferences | `fjo` |
| `models.json` | Provider config with API keys | `fjso` (SECRET) |
| `keybindings.json` | Key bindings | `fjo` |
| `skills/` | Custom skills | `dxRo` (x=exclude .system/) |
| `extensions/` | Extensions | `dRo` |
| `sessions/` | EXCLUDED - ephemeral, per-project |

### Kimi Config Locations (`~/.kimi/`)
| File | Purpose | Flags |
|------|---------|-------|
| `config.toml` | Main config with API keys | `fso` (SECRET) |
| `mcp.json` | MCP server config | `fjso` (SECRET) |
| `sessions/` | EXCLUDED - ephemeral |

### Import Map Updates (`src/lib/import.sh`)

Add to `_IMPORT_SYNC_MAP` array after Cursor entries (~line 491):
```bash
# --- Pi (optional) ---
"/source/.pi/agent/settings.json:/target/pi/settings.json:fjo"
"/source/.pi/agent/models.json:/target/pi/models.json:fjso"
"/source/.pi/agent/keybindings.json:/target/pi/keybindings.json:fjo"
"/source/.pi/agent/skills:/target/pi/skills:dxo"
"/source/.pi/agent/extensions:/target/pi/extensions:do"

# --- Kimi (optional) ---
"/source/.kimi/config.toml:/target/kimi/config.toml:fso"
"/source/.kimi/mcp.json:/target/kimi/mcp.json:fjso"
```

Note: Import map doesn't use `R` flag (remove is only for symlinks).

## Tasks

### fn-35-e0x.1: Research Pi agent
Verify Pi and Kimi config file paths by checking CLI help/docs. Confirm expected file locations.

### fn-35-e0x.2: Add Pi to sync-manifest.toml
Add entries for Pi config files using `o` (optional) flag pattern from Copilot/Gemini.

### fn-35-e0x.3: Add Kimi to sync-manifest.toml
Add entries for Kimi config files. Similar pattern to Pi.

### fn-35-e0x.4: Update _IMPORT_SYNC_MAP
Add Pi and Kimi entries to `src/lib/import.sh` and run `scripts/check-manifest-consistency.sh`.

### fn-35-e0x.5: Build and verify
Run `./src/build.sh`, verify generated files updated, smoke test in container.

## Quick commands

```bash
# Check manifest consistency (before committing)
scripts/check-manifest-consistency.sh

# Build with new entries
./src/build.sh

# Verify agents work in container
cai shell
pi --version
kimi --version

# Test optional sync behavior (inside container)
# cai sync moves config from $HOME to data volume and creates symlink
mkdir -p ~/.pi/agent && echo '{}' > ~/.pi/agent/settings.json
cai sync
readlink ~/.pi/agent/settings.json  # Should show /mnt/agent-data/pi/settings.json
```

## Acceptance

- [ ] Pi entries added to sync-manifest.toml with `o` (optional) flag
- [ ] Kimi entries added to sync-manifest.toml with `o` (optional) flag
- [ ] `_IMPORT_SYNC_MAP` updated in `src/lib/import.sh`
- [ ] `scripts/check-manifest-consistency.sh` passes
- [ ] Image builds successfully
- [ ] Agents work in container (pi --version, kimi --version)
- [ ] `cai sync` creates symlinks when Pi/Kimi configs exist under `$HOME`

Note: Optional entries (`o` flag) are NOT included in generated files (symlinks.sh, init-dirs.sh, link-spec.json). Symlinks are created dynamically by `cai sync` only when the user has config files.

## Dependencies

- **fn-36-rb7**: CLI UX Consistency (for container testing)

## References

- Pi Mono: https://github.com/badlogic/pi-mono
- Kimi CLI: https://github.com/MoonshotAI/kimi-cli
- Existing patterns: sync-manifest.toml lines 30-88 (Claude), 422-467 (Codex)
- Optional agent pattern: Copilot (lines 335-357), Gemini (lines 359-398)
