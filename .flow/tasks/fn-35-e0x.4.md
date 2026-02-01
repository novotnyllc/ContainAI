# fn-35-e0x.4 Update _IMPORT_SYNC_MAP

## Description
Add Pi and Kimi entries to `_IMPORT_SYNC_MAP` in `src/lib/import.sh` and verify consistency.

**Size:** M
**Files:** `src/lib/import.sh`

## Approach

Add Pi and Kimi entries to `_IMPORT_SYNC_MAP` array (~line 491, after Cursor):

```bash
# --- Pi (optional) ---
# Selective sync: config files only, skip sessions/
"/source/.pi/agent/settings.json:/target/pi/settings.json:fjo"
"/source/.pi/agent/models.json:/target/pi/models.json:fjso"
"/source/.pi/agent/keybindings.json:/target/pi/keybindings.json:fjo"
"/source/.pi/agent/skills:/target/pi/skills:dxo"
"/source/.pi/agent/extensions:/target/pi/extensions:do"

# --- Kimi (optional) ---
# Selective sync: config files only, skip sessions/
"/source/.kimi/config.toml:/target/kimi/config.toml:fso"
"/source/.kimi/mcp.json:/target/kimi/mcp.json:fjso"
```

Then verify consistency:
```bash
scripts/check-manifest-consistency.sh
```

## Key context

- Import map doesn't use `R` flag (remove-first is only for symlinks)
- Import map must match sync-manifest.toml for CI to pass
- Flags normalized: manifest `dxRo` → import map `dxo` (no R)

## Acceptance
- [ ] Pi entries added to _IMPORT_SYNC_MAP
- [ ] Kimi entries added to _IMPORT_SYNC_MAP
- [ ] `scripts/check-manifest-consistency.sh` passes
- [ ] Flags correctly normalized (no R in import map)

## Done summary
## Summary

Verified Pi and Kimi entries in `_IMPORT_SYNC_MAP` match sync-manifest.toml. The consistency check passes with all 70 entries validated.

**Changes verified:**
- Pi entries (5): settings.json, models.json, keybindings.json, skills/, extensions/
- Kimi entries (2): config.toml, mcp.json
- All flags correctly normalized (R flag removed in import map per convention)

**Evidence:**
- `scripts/check-manifest-consistency.sh` passes
- All entries at lines 492-504 in src/lib/import.sh
## Evidence
- Commits:
- Tests:
- PRs:
