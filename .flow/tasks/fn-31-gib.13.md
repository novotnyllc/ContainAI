# fn-31-gib.13 Implement cai sync command

## Description
In-container command to move local configs to data volume and replace with symlinks. Includes security validations.

**Scope limitation:** Only processes manifest entries with non-empty `container_link`. Entries like `.gitconfig` with empty `container_link` are copy-only and NOT converted to symlinks.

**Path semantics (critical):**
- `source` = path relative to `$HOME` that contains user data (e.g., `.bash_aliases`)
- `target` = path on volume where data is stored (e.g., `bash/aliases`)
- `container_link` = symlink name in `$HOME` pointing to volume (e.g., `.bash_aliases_imported`)

**cai sync behavior:**
1. Reads manifest entries with non-empty `container_link`
2. For each entry: moves `$HOME/<source>` to `/mnt/agent-data/<target>`
3. Creates symlink at `$HOME/<container_link>` pointing to `/mnt/agent-data/<target>`
4. If `container_link == source`, this is a simple move-and-symlink
5. If `container_link != source`, both paths are handled (source moved, container_link symlinked)

## Acceptance
- [ ] `cai sync` subcommand implemented in `src/lib/sync.sh` or similar
- [ ] Container detection: `/mnt/agent-data` mountpoint (required) AND (/.dockerenv OR cgroup marker) (at least one)
- [ ] Refuses to run if detection fails (test on actual host machine)
- [ ] Only processes entries with non-empty `container_link` value
- [ ] Moves `$HOME/<source>` to `/mnt/agent-data/<target>` (not container_link)
- [ ] Creates symlink at `$HOME/<container_link>` pointing to `/mnt/agent-data/<target>`
- [ ] Handles case where `container_link != source` correctly
- [ ] Symlink-attack prevention: uses `realpath`, rejects paths containing symlinks
- [ ] Path validation: resolved path must be under `/mnt/agent-data`
- [ ] Reports actions: `[OK] ~/.claude -> /mnt/agent-data/claude (moved N files)`
- [ ] `--dry-run` flag shows what would happen without changes

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
