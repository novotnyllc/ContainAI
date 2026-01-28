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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
