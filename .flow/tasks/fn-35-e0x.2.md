# fn-35-e0x.2 Add Pi to sync-manifest.toml

## Description
Add sync-manifest.toml entries for Pi coding agent config files.

**Size:** M
**Files:** `src/sync-manifest.toml`

## Approach

Add Pi entries after the Cursor section (~line 490). Use `o` (optional) flag pattern from Copilot/Gemini.

```toml
# =============================================================================
# PI (Mario Zechner's pi-coding-agent) - Optional
# Config location: ~/.pi/agent/
# Docs: https://github.com/badlogic/pi-mono
# =============================================================================

[[entries]]
source = ".pi/agent/settings.json"
target = "pi/settings.json"
container_link = ".pi/agent/settings.json"
flags = "fjo"  # file, json-init, optional

[[entries]]
source = ".pi/agent/models.json"
target = "pi/models.json"
container_link = ".pi/agent/models.json"
flags = "fjso"  # file, json-init, SECRET, optional

[[entries]]
source = ".pi/agent/keybindings.json"
target = "pi/keybindings.json"
container_link = ".pi/agent/keybindings.json"
flags = "fjo"  # file, json-init, optional

[[entries]]
source = ".pi/agent/skills"
target = "pi/skills"
container_link = ".pi/agent/skills"
flags = "dxRo"  # directory, exclude .system/, remove-first, optional

[[entries]]
source = ".pi/agent/extensions"
target = "pi/extensions"
container_link = ".pi/agent/extensions"
flags = "dRo"  # directory, remove-first, optional
```

## Key context

- Use `o` (optional) flag - Pi is not a primary agent
- Use `x` flag for skills/ to exclude .system/ subdirectories
- No Dockerfile.agents changes needed (optional agents not pre-created)
- Sessions are excluded (ephemeral, per-project)

## Acceptance
- [ ] Pi entries added with `o` (optional) flag
- [ ] Pi models.json marked as secret (fjso flag)
- [ ] Pi skills/ uses `x` flag for .system exclusion
- [ ] Sessions directory excluded

## Done summary
Added 5 Pi agent entries to sync-manifest.toml after the Cursor section (lines 547-581):

1. `.pi/agent/settings.json` - User preferences (fjo)
2. `.pi/agent/models.json` - Provider config with API keys (fjso - SECRET)
3. `.pi/agent/keybindings.json` - Key bindings (fjo)
4. `.pi/agent/skills` - Custom skills directory (dxRo - excludes .system/)
5. `.pi/agent/extensions` - Extensions directory (dRo)

All entries use the `o` (optional) flag consistent with other optional agents (Copilot, Gemini, Aider).
Sessions directory is excluded as ephemeral (per task spec).
## Evidence
- Commits:
- Tests:
- PRs:
