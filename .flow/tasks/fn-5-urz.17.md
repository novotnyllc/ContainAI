# fn-5-urz.17 Simplify tmux to XDG-only paths

## Description
## Overview

Simplify tmux configuration support to only use XDG paths (`~/.config/tmux`), removing legacy path support.

## Current State

- `import.sh` SYNC_MAP: Already only imports XDG paths:
  - `/source/.config/tmux:/target/config/tmux:d`
  - `/source/.local/share/tmux:/target/local/share/tmux:d`
- `entrypoint.sh`: Creates both legacy (`/mnt/agent-data/tmux/`, `/mnt/agent-data/tmux/.tmux`) AND XDG directories
- `Dockerfile` (lines 235-239): Creates XDG symlinks only

## Changes Required

1. **entrypoint.sh** (lines 145-149): Remove legacy tmux directory creation
   - Remove: `ensure_dir "${DATA_DIR}/tmux"`
   - Remove: `ensure_dir "${DATA_DIR}/tmux/.tmux"`
   - Keep: `ensure_dir "${DATA_DIR}/config/tmux"`

2. **test-sync-integration.sh**: Update test to use XDG path
   - Change symlink check from `~/.tmux.conf` to `~/.config/tmux/tmux.conf`
   - Update test assertions accordingly

## Files to Modify

- `agent-sandbox/entrypoint.sh:145-149`
- `agent-sandbox/test-sync-integration.sh:506-549`

## Rationale

- Modern tmux supports XDG paths (`~/.config/tmux/tmux.conf`)
- Legacy `~/.tmux.conf` is deprecated
- Simplifies volume structure and reduces confusion
- SYNC_MAP already only syncs XDG paths, so this aligns implementation
## Acceptance
- [ ] entrypoint.sh no longer creates `/mnt/agent-data/tmux/` directory
- [ ] entrypoint.sh no longer creates `/mnt/agent-data/tmux/.tmux/` directory
- [ ] entrypoint.sh still creates `/mnt/agent-data/config/tmux/` directory
- [ ] test-sync-integration.sh tests XDG path (`~/.config/tmux/`) instead of legacy
- [ ] tmux integration test passes with XDG config location
## Done summary
# fn-5-urz.17 Simplify tmux to XDG-only paths

## Changes Made

1. **entrypoint.sh**: Removed legacy tmux directory creation
   - Removed: `ensure_dir "${DATA_DIR}/tmux"` 
   - Removed: `ensure_dir "${DATA_DIR}/tmux/.tmux"`
   - Kept: `ensure_dir "${DATA_DIR}/config/tmux"`
   - Added: `ensure_dir "${DATA_DIR}/local/share/tmux"` (for XDG data)
   - Updated comment to reflect XDG-only paths

2. **test-sync-integration.sh**: Updated Test 8 to use XDG paths
   - Changed symlink check from `~/.tmux.conf` to `~/.config/tmux`
   - Updated expected target from `/mnt/agent-data/tmux/.tmux.conf` to `/mnt/agent-data/config/tmux`
   - Updated config loading test to use XDG path (`~/.config/tmux/tmux.conf`)
   - Tmux auto-detects XDG config location, so no explicit `-f` flag needed

## Rationale

The Dockerfile already only creates XDG symlinks (`~/.config/tmux` → `/mnt/agent-data/config/tmux`), and the SYNC_MAP only imports XDG paths. This change aligns entrypoint.sh and tests with that reality.
## Evidence
- Commits:
- Tests:
- PRs: