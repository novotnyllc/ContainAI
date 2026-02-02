# fn-32-2mq.5 Implement image pull prompt

## Description

When building a template and no local base image exists, prompt the user with image metadata before pulling.

**Target Artifact:**
The "base image" is `ghcr.io/novotnyllc/containai:<tag>` where tag is determined by channel config (`:latest` for stable, `:nightly` for nightly). This is the image referenced in templates' FROM statement.

**Implementation Location:**
`src/lib/template.sh` - add check in `_cai_build_template()` before Docker build. This ensures:
1. Correct Docker context is used (containai-docker if configured)
2. Prompt happens at the right point in the build flow
3. Template-specific logic is centralized

**Flow:**
1. In `_cai_build_template()`, before `docker build`:
2. Determine base image from channel: `_cai_base_image`
3. Check if image exists locally: `docker image inspect "$image" >/dev/null 2>&1`
4. If not present, query registry for metadata (use `src/lib/registry.sh`)
5. Display prompt using `_cai_notice()` (new function, always visible):
```
[NOTICE] No local ContainAI base image found.
         Image: ghcr.io/novotnyllc/containai:latest
         Size: ~2.1 GB (compressed)
         Published: 2026-01-15

Pull image? [Y/n]:
```
6. If user confirms (or CAI_YES=1), pull image and continue with build
7. If user declines, exit with message about required image

**Metadata Fetching:**
- Use helper functions from `src/lib/registry.sh` (created in fn-32-2mq.6)
- Timeout after 2s, cache results
- On failure: skip size/date display, just show image name

**Non-Interactive Mode:**
- If stdin is not a TTY and CAI_YES not set: exit with error
- If CAI_YES=1: pull without prompting

## Acceptance

- [x] Image check added to `_cai_build_template()` in `src/lib/template.sh`
- [x] Detects when base image is not present locally
- [x] Queries registry for image metadata (size, date from OCI labels)
- [x] Displays image name, approximate size, and publish date
- [x] Uses `[NOTICE]` level message (always visible, not gated by --verbose)
- [x] Prompts user with `[Y/n]` confirmation (default yes)
- [x] Respects CAI_YES=1 for non-interactive pull
- [x] Exits with clear error if user declines pull
- [x] Exits with error in non-interactive mode without CAI_YES
- [x] Continues to template build after successful pull
- [x] Handles registry timeout gracefully (skips metadata, still prompts)
- [x] Uses correct Docker context for the pull operation

## Done summary
## Summary

Implemented image pull prompt in `_cai_build_template()` that detects when the ContainAI base image is missing locally and prompts the user before pulling.

### Key Changes

1. **New `_cai_notice()` function** in `src/lib/core.sh`:
   - Always-visible NOTICE level logging (not gated by --verbose)

2. **New `src/lib/registry.sh` module** with:
   - `_cai_base_image()` - returns channel-aware base image (`:latest` or `:nightly`)
   - `_cai_ghcr_token()` - anonymous GHCR token acquisition
   - `_cai_ghcr_manifest_digest()` - manifest digest via HEAD request
   - `_cai_ghcr_image_metadata()` - fetch and cache image metadata (2s timeout)
   - `_cai_format_size()` - human-readable byte formatting
   - Registry cache with 60-minute TTL in `~/.config/containai/cache/registry/`

3. **New `_cai_ensure_base_image()` function** in `src/lib/template.sh`:
   - Checks if base image exists locally using `docker image inspect`
   - Queries registry for metadata with graceful degradation on timeout
   - Displays `[NOTICE]` with image name and approximate size
   - Prompts with `[Y/n]` confirmation (default yes)
   - Respects `CAI_YES=1` for non-interactive auto-confirm
   - Handles non-interactive mode with clear error message
   - Uses correct Docker context for pull operation

### Files Modified
- `src/lib/core.sh` - Added `_cai_notice()` function
- `src/lib/registry.sh` - New module with registry API helpers
- `src/lib/template.sh` - Added `_cai_ensure_base_image()` and integrated into `_cai_build_template()`
- `src/containai.sh` - Added sourcing of `registry.sh`
- `tests/integration/test-templates.sh` - Added Tests 13b and 13c for validation
## Evidence
- Commits:
- Tests: test_file, test_names, passing, new_tests
- PRs:
