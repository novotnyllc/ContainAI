# fn-12-css.7 Implement .env file discovery and merging

## Description

Create a hierarchical .env file system where environment variables cascade from global defaults → volume-specific → workspace-specific overrides. This replaces the host env sniffing approach with explicit, auditable files.

**File hierarchy (lowest to highest precedence):**

1. `~/.config/containai/default.env` - Global defaults for all containers
2. `~/.config/containai/volumes/<volume-name>.env` - Per-volume overrides
3. `<workspace>/.containai/env` - Per-workspace overrides (note: no .env extension for clarity)

**Merge behavior:**
- Later files override earlier values
- If a file doesn't exist, skip it (no error)
- Final merged result is what gets imported to container

**Directory structure:**
```
~/.config/containai/
├── config.toml
├── default.env          # Global env defaults
└── volumes/
    ├── myapp-data.env   # Per-volume env
    └── other-vol.env

/workspace/project/
└── .containai/
    └── env              # Per-workspace env
```

**Implementation:**

Add to lib/env.sh:
- `_containai_find_env_files()` - Returns ordered list of .env files to merge
- `_containai_merge_env_files()` - Merges files in order, returns combined key=value pairs
- Update `_containai_import_env()` to use merged env instead of host env

**File format:**
- Standard .env format (already supported by existing parser)
- Comments with `#`
- `KEY=value` format
- No shell expansion (literal values)

**Security:**
- Only files in known locations are read
- Workspace .env must be within workspace (no `../` escape)
- Symlinks rejected (same as current behavior)

## Acceptance

- [ ] `~/.config/containai/default.env` is loaded for all containers
- [ ] `~/.config/containai/volumes/<volume>.env` is loaded for specific volume
- [ ] `<workspace>/.containai/env` is loaded for workspace
- [ ] Later files override earlier values
- [ ] Missing files are skipped silently
- [ ] Merge result is correctly passed to env import
- [ ] volumes/ directory is created if needed

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
