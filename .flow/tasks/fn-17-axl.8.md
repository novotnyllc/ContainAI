# fn-17-axl.8 User-specified additional files config

## Description

Allow users to specify additional files/directories to sync via TOML configuration.

**Config syntax:**
```toml
# In ~/.config/containai/config.toml or .containai/config.toml

[import]
additional_paths = [
    "~/.my-tool/config.json",
    "~/.my-other-tool/",
]
```

**Implementation:**
1. Add `[import]` section to config schema in `src/lib/config.sh`
2. Parse `additional_paths` array
3. Validate paths:
   - Must start with `~/` or be absolute under $HOME
   - No traversal outside $HOME
4. Add to sync entries at runtime (append to _IMPORT_SYNC_MAP equivalent)
5. Target path mirrors source structure under `/target/`

**Destination mapping:**
- `~/.my-tool/config.json` → `/target/my-tool/config.json`
- `~/.my-other-tool/` → `/target/my-other-tool/`

**Security:**
- Paths must resolve to within $HOME
- No symlink following for validation

## Acceptance

- [ ] `[import]` section added to config schema
- [ ] `additional_paths` array parsed correctly
- [ ] User-specified files synced on `cai import`
- [ ] User-specified directories synced recursively
- [ ] Paths validated (must be under $HOME)
- [ ] Path traversal attempts rejected with error
- [ ] `cai import --dry-run` shows additional paths
- [ ] Works with workspace-specific config
- [ ] Documented in docs/configuration.md

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
