# fn-12-css.10 Add .priv. exclusion to import

## Description

Add automatic exclusion of `.bashrc.d/*.priv.*` files during import. This prevents accidental import of host-specific private configuration that shouldn't be shared with containers.

**Pattern:**
- Files matching `*.priv.*` in `.bashrc.d/` are excluded
- Examples that would be excluded:
  - `~/.bashrc.d/01_secrets.priv.sh`
  - `~/.bashrc.d/work.priv.bash`
  - `~/.bashrc.d/personal.priv.aliases`
- Examples that would NOT be excluded:
  - `~/.bashrc.d/01_aliases.sh` (no .priv.)
  - `~/.bashrc.d/private/secrets.sh` (priv in dir, not file)
  - `~/.config/priv.env` (not in .bashrc.d)

**Implementation:**

1. Add to default excludes in lib/import.sh:
   ```bash
   _IMPORT_DEFAULT_EXCLUDES+=(
       ".bashrc.d/*.priv.*"
   )
   ```

2. Add config option to control behavior:
   ```toml
   [import]
   exclude_priv = true  # Default: true
   ```

3. If `exclude_priv = false`, don't add the .priv. pattern to excludes

**Rationale:**
- Users often have private bash configs with secrets, API keys, work-specific aliases
- These should not automatically flow into containers
- Convention: name files with `.priv.` to mark as host-only
- Explicit and discoverable pattern

**Rsync implementation:**
- Pattern added to `--exclude` list passed to rsync
- Same mechanism as existing `default_excludes`
- Pattern is relative to sync source (.bashrc.d)

## Acceptance

- [ ] `~/.bashrc.d/secrets.priv.sh` is not imported
- [ ] `~/.bashrc.d/aliases.sh` IS imported
- [ ] `import.exclude_priv = false` allows .priv. files
- [ ] Pattern works in dry-run output
- [ ] Pattern works with rsync-based import

## Done summary
Superseded by fn-36-rb7 or fn-31-gib
## Evidence
- Commits:
- Tests:
- PRs:
