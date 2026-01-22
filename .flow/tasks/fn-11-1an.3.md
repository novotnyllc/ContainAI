# fn-11-1an.3 Add symlink relinking to dry-run output

## Description
Add symlink relinking preview to `--dry-run` output so users can see what symlinks will be relinked.

**Size:** S
**Files:** `src/lib/import.sh` (dry-run handling, lines ~500-600)

## Approach

1. In dry-run mode, after listing files that would sync, add symlink analysis:
   - Detect symlinks in source directories
   - For each, show: `[RELINK] /source/link -> /target/new_target`
   - For external symlinks: `[WARN] /source/link -> /external/path (outside import tree)`

2. Follow existing dry-run output pattern at `src/lib/import.sh:579-614`
## Acceptance
- [ ] `--dry-run` shows symlinks that would be relinked
- [ ] `--dry-run` shows warnings for external symlinks
- [ ] Output format matches existing dry-run style
- [ ] No actual changes made during dry-run
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
