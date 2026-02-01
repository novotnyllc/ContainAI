# fn-42-cli-ux-fixes-hostname-reset-wait-help.4 Symlink .gitconfig to data volume for persistence

## Description
Change `.gitconfig` from copied file to symlink pointing to data volume, so git config changes inside container persist across restarts. Also strip signing config on import.

**Size:** S
**Files:** `src/sync-manifest.toml`, `src/lib/import.sh`

## Approach

Follow pattern from `.gitignore_global`:

1. Update `src/sync-manifest.toml`:
   ```toml
   source = ".gitconfig"
   target = "git/gitconfig"
   container_link = ".gitconfig"
   flags = "fg"  # g = git-filter
   ```

2. Update git-filter logic in `src/lib/import.sh` to strip:
   - `credential.helper` (existing)
   - `user.signingkey`
   - `commit.gpgsign`
   - `tag.gpgsign`
   - `gpg.program`
   - `gpg.format`

3. Update `_IMPORT_SYNC_MAP` to match manifest

4. Ensure `git/` directory created in data volume

5. Run `scripts/check-manifest-consistency.sh` to verify

## Key context

- Sync manifest is authoritative source (per CLAUDE.md)
- `g` flag triggers git-filter function
- Signing config must be stripped for security (keys don't exist in container)
- Pattern reference: `.gitignore_global` uses symlink approach
## Approach

Follow pattern from `.gitignore_global`:

1. Update `src/sync-manifest.toml`:
   ```toml
   # Before:
   source = ".gitconfig"
   target = ".gitconfig"
   flags = "fg"

   # After:
   source = ".gitconfig"
   target = "git/gitconfig"
   container_link = ".gitconfig"
   flags = "fg"
   ```

2. Update `_IMPORT_SYNC_MAP` in `src/lib/import.sh` to match manifest

3. Ensure `git/` directory created in data volume (check `entrypoint.sh` or `init-dirs.sh`)

4. Run `scripts/check-manifest-consistency.sh` to verify alignment

## Key context

- Sync manifest is authoritative source (per CLAUDE.md)
- `container_link` creates symlink from `~/.gitconfig` → `/mnt/agent-data/git/gitconfig`
- `g` flag strips `credential.helper` during import (security)
- Pattern reference: `.gitignore_global` already does this
## Acceptance
- [ ] `.gitconfig` stored in data volume at `git/gitconfig`
- [ ] `~/.gitconfig` symlinked to data volume location
- [ ] Git config changes inside container persist across restarts
- [ ] `credential.helper` stripped on import
- [ ] Signing config stripped: `user.signingkey`, `commit.gpgsign`, `tag.gpgsign`, `gpg.program`, `gpg.format`
- [ ] Manifest consistency check passes
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
