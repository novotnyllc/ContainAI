# fn-36-rb7.11 Update container lookup helper

## Description
Update `_cai_find_workspace_container` to check workspace state first, then labels, then naming fallbacks. Ensure `_cai_resolve_container_name` handles collision suffixes up to `-99`.

## Acceptance
- [ ] Lookup order: (1) workspace config, (2) workspace label, (3) new naming, (4) legacy hash
- [ ] If workspace config has `container_name`, check for existence first
- [ ] Falls through if config entry missing or container gone
- [ ] Returns container name (not ID)
- [ ] `_cai_resolve_container_name` appends `-2`, `-3`, etc. on collisions
- [ ] Collision check uses workspace label to detect different workspace
- [ ] Errors if suffix exceeds `-99`

## Verification
- [ ] Create container and verify lookup via each method
- [ ] Create collision with different workspace and verify suffix increment

## Done summary
# fn-36-rb7.11 Summary: Update container lookup helper

## Changes Made

### `_cai_find_workspace_container` (src/lib/container.sh:434)

Updated lookup order to check workspace config first:

1. **Workspace config** (NEW): Check `container_name` from user config via `_containai_read_workspace_key()`. If saved and container exists in Docker, return it. Falls through if config entry missing or container gone.
2. **Label match**: containai.workspace=<resolved-path>
3. **New naming format**: result from `_containai_container_name()`
4. **Legacy hash format**: result from `_containai_legacy_container_name()`

### `_cai_resolve_container_name` (src/lib/container.sh:630)

Updated collision handling:

- Changed max suffix from `-999` to `-99` per spec
- Collision detection uses workspace label (`containai.workspace`) to detect if container belongs to different workspace
- Appends `-2`, `-3`, etc. up to `-99` on collisions
- Error if suffix exceeds `-99`

## Files Modified

- `src/lib/container.sh` - Updated `_cai_find_workspace_container` and `_cai_resolve_container_name`

## Verification

- shellcheck passes
- Bash syntax check passes
## Evidence
- Commits:
- Tests: shellcheck -x src/lib/container.sh, bash -n src/lib/container.sh
- PRs:
