# fn-35-e0x.3 Add Kimi to sync-manifest.toml

## Description
Add sync-manifest.toml entries for Kimi CLI config files.

**Size:** S
**Files:** `src/sync-manifest.toml`

## Approach

Add Kimi entries after Pi section. Use `o` (optional) flag pattern.

```toml
# =============================================================================
# KIMI CLI (MoonshotAI) - Optional
# Config location: ~/.kimi/
# Docs: https://github.com/MoonshotAI/kimi-cli
# =============================================================================

[[entries]]
source = ".kimi/config.toml"
target = "kimi/config.toml"
container_link = ".kimi/config.toml"
flags = "fso"  # file, SECRET, optional

[[entries]]
source = ".kimi/mcp.json"
target = "kimi/mcp.json"
container_link = ".kimi/mcp.json"
flags = "fjso"  # file, json-init, SECRET, optional
```

## Key context

- Use `o` (optional) flag - Kimi is not a primary agent
- Both config files are SECRET (contain API keys)
- Sessions are excluded (ephemeral)
- No Dockerfile.agents changes needed (optional agents not pre-created)

## Acceptance
- [ ] Kimi entries added with `o` (optional) flag
- [ ] config.toml marked as secret (fso flag)
- [ ] mcp.json marked as secret (fjso flag)

## Done summary
## Summary
Added Kimi CLI sync-manifest.toml entries for config syncing between host and container.

## Changes
- Added `[[entries]]` for `.kimi/config.toml` with flags `fso` (file, SECRET, optional)
- Added `[[entries]]` for `.kimi/mcp.json` with flags `fjso` (file, json-init, SECRET, optional)
- Positioned after Pi section, before container-only symlinks section

## Flags explained
- `f` = file type
- `s` = secret (600 permissions, skipped with --no-secrets)
- `j` = json-init (create `{}` if empty)
- `o` = optional (skip if source doesn't exist; don't pre-create in Dockerfile)
## Summary
Added Kimi CLI sync-manifest.toml entries for config syncing between host and container.

## Changes
- Added `[[entries]]` for `.kimi/config.toml` with flags `fso` (file, SECRET, optional)
- Added `[[entries]]` for `.kimi/mcp.json` with flags `fjso` (file, json-init, SECRET, optional)
- Positioned after Pi section, before container-only symlinks section

## Flags explained
- `f` = file type
- `s` = secret (600 permissions, skipped with --no-secrets)
- `j` = json-init (create `{}` if empty)
- `o` = optional (skip if source doesn't exist; don't pre-create in Dockerfile)
## Evidence
- Commits:
- Tests:
- PRs:
