# fn-12-css.9 Update cai import to use .env hierarchy

## Description

Update the `cai import` command to use the new .env file hierarchy instead of host environment variables. This integrates tasks 7 and 8 into the import workflow.

**Changes to cai import:**

1. **Before import:**
   - Discover .env files using `_containai_find_env_files()`
   - Merge them using `_containai_merge_env_files()`
   - Apply `[env].import` allowlist filter to merged result

2. **During import:**
   - Write filtered env vars to volume (existing mechanism)
   - Show what env vars were imported in verbose/dry-run mode

3. **Verbose output:**
   ```
   Importing environment variables:
     From: ~/.config/containai/default.env (3 vars)
     From: ~/.config/containai/volumes/myapp-data.env (1 var)
     From: /workspace/.containai/env (2 vars)
     Filtered to: 4 vars (by [env].import allowlist)
   ```

**Implementation:**

Update lib/import.sh `_containai_import_cmd()`:
1. Replace host env reading with .env file hierarchy
2. Call `_containai_merge_env_files()` before env import step
3. Pass merged result to `_containai_import_env()`
4. Add verbose output showing sources

**No changes to:**
- File sync (rsync) - unchanged
- Hot-reload - unchanged
- Archive restore - unchanged

**The [env].import allowlist:**
- Still respected - only vars in allowlist are imported
- Now filters the merged .env content instead of host env
- If allowlist is empty, no env vars imported (explicit opt-in)

## Acceptance

- [ ] `cai import` reads from .env file hierarchy
- [ ] `[env].import` allowlist filters merged .env content
- [ ] Empty allowlist means no env vars imported
- [ ] Verbose mode shows which files were read
- [ ] Dry-run shows what would be imported
- [ ] Hot-reload uses same .env hierarchy

## Done summary
Superseded by fn-36-rb7 or fn-31-gib
## Evidence
- Commits:
- Tests:
- PRs:
