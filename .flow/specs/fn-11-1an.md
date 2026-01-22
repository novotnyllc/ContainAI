# Symlink Relinking During Import

## Overview

When importing from a directory (`cai import --from <dir>`), symlinks that point to locations within the import source are preserved as-is by rsync. This means symlinks end up pointing to the original host paths instead of the new container paths, resulting in broken or incorrectly-targeted symlinks.

**Example:**
- Host: `/host/dotfiles/nvim` (directory)
- Host: `/host/dotfiles/.config/nvim` → symlink to `/host/dotfiles/nvim`
- After import: `/mnt/agent-data/config/nvim` → still points to `/host/dotfiles/nvim` (wrong!)
- Should be: `/mnt/agent-data/config/nvim` → `/mnt/agent-data/nvim`

## Scope

**In scope:**
- Symlinks within sync-mode imports (`--from <dir>`)
- Both relative and absolute symlinks whose targets are within the import tree
- Warning/logging for symlinks pointing outside the import tree

**Out of scope:**
- Archive restore mode (tgz) - symlinks intentionally rejected for security
- Symlinks pointing outside the import tree (cannot be relinked)
- Cross-SYNC_MAP symlink relinking (complex, defer to future)

## Quick commands

```bash
# Run integration tests for import
./tests/integration/test-sync-integration.sh

# Check symlinks in volume
docker run --rm -v containai-data:/data alpine find /data -type l -exec ls -la {} \;
```

## Acceptance

- [ ] Symlinks within the import source tree are relinked to point to correct container paths
- [ ] Relative symlinks remain relative after relinking
- [ ] Absolute symlinks are converted to container-absolute paths
- [ ] Symlinks pointing outside import tree are preserved as-is with warning
- [ ] Broken symlinks on host are preserved as-is (no error)
- [ ] Circular symlink chains do not cause infinite loops
- [ ] `--dry-run` shows symlinks that would be relinked
- [ ] Existing integration tests continue to pass
- [ ] New integration test validates symlink relinking

## Security

- Relinked symlinks MUST resolve under `/mnt/agent-data/` only (no escape)
- Use `realpath -m` to validate final target before creating symlink
- Archive restore symlink rejection (`_import_restore_from_tgz`) remains unchanged

## References

- Import implementation: `src/lib/import.sh:464-967`
- SYNC_MAP entries: `src/lib/import.sh:348-408`
- POSIX sh copy script: `src/lib/import.sh:731-936`
- Symlink pitfall: `.flow/memory/pitfalls.md:26` (`ln -sfn` directory gotcha)
- Archive symlink rejection: `src/lib/import.sh:133-328`
- fn-9-mqv symlink limitation: `.flow/specs/fn-9-mqv.md:162-179`
