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
Implemented [import].additional_paths config option for user-specified files/directories to sync via cai import. Includes comprehensive security validation: rejects colons, relative paths, symlinks (both components and final targets), and paths outside HOME. Uses lexical normalization (no symlink following) per spec.
## Evidence
- Commits: cd93a4530c8fbe1dcb05aba35feb59f12b0c7459, c04e4367c2a03f26ac8dbf61e4c1a4e8f39cae0e, 02405ec1447b9c3e0b4ea15adb6b2f2a36af59b7, b5e5a21bc15897c73e55ea1d46df5cfc1fb4a9cb, b1b80e67952126adc4f067047a9761f58af10427
- Tests: bash tests/unit/test-exclude-rewrite.sh, shellcheck -x src/lib/config.sh src/lib/import.sh
- PRs:
