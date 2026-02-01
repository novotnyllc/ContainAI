# fn-35-e0x.1 Research Pi agent

## Description
Verify Pi and Kimi config file paths by checking CLI help/docs. Confirm expected file locations.

**Size:** S
**Files:** None (research only)

## Approach

Run the CLIs **inside the container** to verify config paths (CLIs are installed in Docker image, not on host):
```bash
# Enter container
cai shell

# Check Pi help for config location
pi --help 2>&1 | head -50
ls -la ~/.pi/agent/ 2>/dev/null || echo "No Pi config yet"

# Check Kimi help for config location
kimi --help 2>&1 | head -50
ls -la ~/.kimi/ 2>/dev/null || echo "No Kimi config yet"
```

Alternatively, check the upstream documentation:
- Pi: https://github.com/badlogic/pi-mono
- Kimi: https://github.com/MoonshotAI/kimi-cli

### Expected Paths (to verify)

**Pi Agent (`~/.pi/agent/`):**
- settings.json - user preferences
- models.json - API keys (SECRET)
- keybindings.json - key bindings
- skills/ - custom skills
- extensions/ - extensions
- sessions/ - EXCLUDED (ephemeral)

**Kimi CLI (`~/.kimi/`):**
- config.toml - main config with API key (SECRET)
- mcp.json - MCP server config (SECRET)
- sessions/ - EXCLUDED (ephemeral)

## Key context

- Pi is `@mariozechner/pi-coding-agent` by badlogic, NOT Inflection's Pi
- Kimi is MoonshotAI's CLI coding assistant
- Both are already installed in Docker image
- Verify paths before adding to manifest

## Acceptance
- [ ] Pi config location verified
- [ ] Kimi config location verified
- [ ] All expected files documented

## Done summary
## Research Summary: Pi & Kimi Config Paths

### Pi Agent (`~/.pi/agent/`)

**Confirmed paths from pi-mono documentation:**

| File/Dir | Purpose | Sync Flag | Notes |
|----------|---------|-----------|-------|
| `settings.json` | User preferences | `fjo` | JSON config |
| `models.json` | Provider config with API keys | `fjso` | SECRET - contains API keys |
| `keybindings.json` | Key bindings | `fjo` | JSON config |
| `skills/` | Custom skills packages | `dxRo` | Exclude `.system/` subdirectory |
| `extensions/` | TypeScript extension modules | `dRo` | User extensions |
| `SYSTEM.md` | Global system prompt | N/A | Per-project customization, not synced |
| `AGENTS.md` | Global project instructions | N/A | Per-project customization, not synced |
| `prompts/` | Reusable prompt templates | N/A | Per-project customization, not synced |
| `themes/` | Custom UI themes | N/A | Per-project customization, not synced |
| `sessions/` | Session data | EXCLUDED | Ephemeral, per-project |
| `git/` | Global git packages | EXCLUDED | Package cache, can rebuild |
| `npm/` | Global npm packages | EXCLUDED | Package cache, can rebuild |

**Environment override:** `PI_CODING_AGENT_DIR` (defaults to `~/.pi/agent/`)

### Kimi CLI (`~/.kimi/`)

**Confirmed paths from kimi-cli source code:**

| File/Dir | Purpose | Sync Flag | Notes |
|----------|---------|-----------|-------|
| `config.toml` | Main config with API key | `fso` | SECRET - contains API key |
| `mcp.json` | MCP server config | `fjso` | SECRET - may contain credentials |
| `sessions/` | Session data | EXCLUDED | Ephemeral, organized by MD5 hash of work dirs |

**Environment override:** `KIMI_SHARE_DIR` (defaults to `~/.kimi/`)

### Scope Decision

**Recommend syncing (minimal set):**
- Pi: `settings.json`, `models.json`, `keybindings.json`, `skills/`, `extensions/`
- Kimi: `config.toml`, `mcp.json`

**Recommend NOT syncing:**
- Pi: `SYSTEM.md`, `AGENTS.md`, `prompts/`, `themes/` - these are per-project customizations, not global config
- Pi: `git/`, `npm/` - package caches that can be rebuilt
- Both: `sessions/` - ephemeral data

### Sources (verified 2026-02-01)
- Pi: https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent (README.md documents ~/.pi/agent/ structure)
- Kimi: https://github.com/MoonshotAI/kimi-cli
  - `src/kimi_cli/share.py`: `get_share_dir()` returns `~/.kimi/` (with `KIMI_SHARE_DIR` env override)
  - `src/kimi_cli/config.py`: `get_config_file()` returns `{share_dir}/config.toml`
  - `src/kimi_cli/cli/mcp.py`: `get_global_mcp_config_file()` returns `{share_dir}/mcp.json`

## Evidence
- Commits:
- Tests:
- PRs:
