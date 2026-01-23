# fn-10-vep.54 Add --image-tag parameter to _cai_find_container

## Description
Add --image-tag parameter to _cai_find_container for debugging/advanced use.

**Size:** S
**Files:** lib/container.sh

## Approach

1. Add `--image-tag` parameter to CLI:
   - Used for debugging or forcing specific image
   - Stored in container label if used
   - Not required in normal use (simplified naming)

2. Update `_cai_find_container()` to accept optional image_tag:
   - If provided, filter by `containai.image-tag` label
   - For advanced users who want multiple images per workspace

## Key context

- User note: "--image-tag parameter missing"
- This is for advanced/debugging use, not normal workflow
- Simplified naming (fn-10-vep.52) is the default path
## Acceptance
- [ ] `--image-tag` parameter added to `cai run` and `cai shell`
- [ ] When used, stored as `containai.image-tag` label
- [ ] `_cai_find_container()` can filter by image-tag
- [ ] Not required for normal use (optional parameter)
- [ ] Documented as advanced/debugging feature
## Done summary
## Summary

The `--image-tag` parameter for `_cai_find_container` was already fully implemented:

1. **CLI parameter added**: `--image-tag` is accepted by both `cai run` and `cai shell` commands
2. **Label storage**: When `--image-tag` is used, it's stored as the `containai.image-tag` label on the container
3. **Container filtering**: `_cai_find_container()` accepts an optional third parameter `image_tag_filter` that filters containers by the `containai.image-tag` label
4. **Optional usage**: The parameter is not required; when omitted, default behavior applies (one container per workspace)
5. **Documentation**: Help text documents this as an "advanced/debugging" feature

The implementation supports advanced use cases where users want to run multiple images for the same workspace, while keeping the default experience simple (one container per workspace path).
## Evidence
- Commits:
- Tests:
- PRs: