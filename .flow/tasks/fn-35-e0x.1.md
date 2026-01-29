# fn-35-e0x.1 Research Pi agent

## Description
Add sync-manifest.toml entries for both Pi coding agent and Kimi CLI.

**Size:** M
**Files:** `src/sync-manifest.toml`

## Approach

Follow existing patterns from Claude (lines 30-88) and Codex (lines 422-467).

### Pi Entries (`~/.pi/agent/`)
```toml
# =============================================================================
# PI (Mario Zechner's pi-coding-agent)
# =============================================================================

[[entries]]
source = ".pi/agent/settings.json"
target = "pi/settings.json"
container_link = ".pi/agent/settings.json"
flags = "fj"

[[entries]]
source = ".pi/agent/models.json"
target = "pi/models.json"
container_link = ".pi/agent/models.json"
flags = "fjs"  # SECRET - contains API keys

[[entries]]
source = ".pi/agent/keybindings.json"
target = "pi/keybindings.json"
container_link = ".pi/agent/keybindings.json"
flags = "fj"

[[entries]]
source = ".pi/agent/skills"
target = "pi/skills"
container_link = ".pi/agent/skills"
flags = "dR"

[[entries]]
source = ".pi/agent/extensions"
target = "pi/extensions"
container_link = ".pi/agent/extensions"
flags = "dR"
```

### Kimi Entries (`~/.kimi/`)
```toml
# =============================================================================
# KIMI CLI (MoonshotAI)
# =============================================================================

[[entries]]
source = ".kimi/config.toml"
target = "kimi/config.toml"
container_link = ".kimi/config.toml"
flags = "fs"  # SECRET

[[entries]]
source = ".kimi/mcp.json"
target = "kimi/mcp.json"
container_link = ".kimi/mcp.json"
flags = "fjs"  # SECRET
```

## Key context

- Sessions directories are excluded (ephemeral, per-project)
- Pi uses `~/.pi/agent/` not `~/.pi/`
- `fjs` = file + json-init + secret
- `dR` = directory + remove existing first
## Acceptance
- [ ] Pi entries added with correct paths (~/.pi/agent/)
- [ ] Pi models.json marked as secret (fjs flag)
- [ ] Kimi entries added with correct paths (~/.kimi/)
- [ ] Kimi config.toml marked as secret (fs flag)
- [ ] Sessions excluded for both agents
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
