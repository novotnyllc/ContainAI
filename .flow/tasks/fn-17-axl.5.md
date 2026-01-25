# fn-17-axl.5 Gitconfig filtering: strip credential.helper

## Description

When importing `~/.gitconfig`, strip all `credential.helper` configuration lines to prevent the container from using host credential managers (which won't work).

**Why:** Host gitconfig may have `credential.helper=osxkeychain` or similar that won't function in the container and causes confusing errors.

**Implementation:**
1. Add gitconfig to sync manifest with new `g` flag (git-filter)
2. In rsync script or post-processing, filter out lines matching:
   - `credential.helper = ...`
   - `[credential]` section (if only contains helper)
3. Preserve all other gitconfig settings
4. Handle multi-line values correctly
5. Also sync `~/.gitignore_global` (no filtering needed)

**Filter rules:**
- Remove lines starting with `[[:space:]]*credential.helper[[:space:]]*=`
- If `[credential]` section becomes empty after removal, remove the section header too
- Preserve comments and other settings

## Acceptance

- [ ] ~/.gitconfig synced to container
- [ ] All `credential.helper` lines stripped
- [ ] Empty `[credential]` sections removed
- [ ] Other gitconfig settings preserved (user.name, user.email, aliases, etc.)
- [ ] Multi-line credential.helper values handled
- [ ] ~/.gitignore_global synced (if exists)
- [ ] `cai import --dry-run` shows gitconfig filtering
- [ ] Container git commands work without credential.helper errors

## Done summary
Added gitconfig filtering to strip credential.helper lines (including multi-line values) and remove empty [credential] sections. Also added .gitignore_global sync via rsync and container symlink.
## Evidence
- Commits: 6c98c1915d1b510e44394e349c4a40337ef41c32, 2a962e1a5cc0a135294260a9ead567252aa248f9
- Tests: shellcheck -x src/lib/import.sh, manual awk filter tests with multi-line gitconfig values
- PRs:
