# fn-10-vep.52 Simplify container naming to per-workspace only

## Description
Simplify container naming to per-workspace only (remove per-image complexity).

**Size:** S
**Files:** lib/container.sh

## Approach

1. Update `_cai_container_name()`:
   - Remove image_ref from hash input
   - Formula: `containai-$(hash "$workspace_path")`
   - One container per workspace (not per workspace+image)

2. Remove multi-container disambiguation logic:
   - No more `--agent` or `--image-tag` for container selection
   - Single container per workspace always

3. Update labels:
   - Keep `containai.workspace` label
   - Remove `containai.image` label (no longer needed for lookup)

## Key context

- Simplification: no need for multiple containers per workspace
- Previous multi-image design was for Docker sandbox limitations
- SSH-based model doesn't have those constraints
## Acceptance
- [ ] Container naming uses workspace-only hash
- [ ] One container per workspace (no multi-container)
- [ ] `--agent` and `--image-tag` flags removed from shell/run
- [ ] Container labels updated (workspace only)
- [ ] Existing container lookup simplified
- [ ] No "multiple containers" disambiguation error
## Done summary
Simplified container naming to per-workspace only by removing --agent and --image-tag flags from CLI, removing image mismatch checks, and using default image for all containers. One container per workspace, named by workspace path hash.
## Evidence
- Commits: 74f159840e38985f383ffe43518fe4b2aec41797
- Tests: bash -n src/containai.sh, bash -n src/lib/container.sh
- PRs: