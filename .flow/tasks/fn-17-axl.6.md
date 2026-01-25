# fn-17-axl.6 Import overrides mechanism

## Description

Allow users to override any imported file by placing files in `~/.config/containai/import-overrides/`.

**How it works:**
1. Normal import runs first (from $HOME or --from source)
2. After main import, scan `~/.config/containai/import-overrides/`
3. For each file found, rsync it to the corresponding target location
4. Overrides completely replace (no merge) the original file

**Directory structure:**
```
~/.config/containai/import-overrides/
├── .gitconfig              # Overrides ~/.gitconfig
├── .claude/
│   └── settings.json       # Overrides ~/.claude/settings.json
└── .config/
    └── starship.toml       # Overrides ~/.config/starship.toml
```

**Security rules:**
1. Only regular files and directories allowed
2. Symlinks are NOT followed (skip with warning)
3. Path traversal (`..`) is rejected
4. Absolute paths in override directory are rejected
5. Paths validated before copy

**Implementation:**
1. Add `_import_apply_overrides()` function to import.sh
2. Call after main sync completes
3. Use `find` to enumerate override files
4. Validate each path before applying
5. Rsync with --mkpath to handle nested directories

## Acceptance

- [ ] Overrides from ~/.config/containai/import-overrides/ applied
- [ ] Override replaces entire file (not merge)
- [ ] Nested directory structures work (e.g., .claude/settings.json)
- [ ] Symlinks in override dir skipped with warning
- [ ] `..` in paths rejected with error
- [ ] Absolute symlink targets rejected
- [ ] `cai import --dry-run` shows override applications
- [ ] Overrides applied after main import (correct precedence)
- [ ] Missing override dir is not an error (just skipped)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
