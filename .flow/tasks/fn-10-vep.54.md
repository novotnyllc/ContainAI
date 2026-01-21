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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
