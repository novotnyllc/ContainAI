# fn-44-build-system-net-project-restructuring.1 Fix Docker build image prefix and local fallback

## Description
Fix the Docker build to use correct default image prefix (ghcr.io), consistent layer naming (`agents` not `full`), and conditional build-arg passing. Also fix `cai refresh` to check local images and compare digests before pulling.

**Size:** M
**Files:**
- `src/build.sh`
- `src/lib/update.sh`

## Approach

1. **Fix default image prefix**: Change default `IMAGE_PREFIX` from `containai` to `ghcr.io/novotnyllc/containai` so builds use the correct registry by default.

2. **Rename layer from `full` to `agents`**:
   - Change `IMAGE_FULL` to `IMAGE_AGENTS` at `src/build.sh:300`
   - Update `--layer` flag validation at line 65 to accept `agents` instead of `full`
   - Update help text at line 9 to show `--layer base|sdks|agents|all`
   - Update any build order messages referencing "full"

3. **Conditional build-arg passing**: Only pass `--build-arg BASE_IMAGE=...` when the local image exists. If not, let Dockerfile defaults handle the pull:
   ```bash
   # For each layer build (e.g., sdks needs base):
   if docker image inspect "${IMAGE_PREFIX}/base:latest" >/dev/null 2>&1; then
       # Local image exists - use it
       build_layer "sdks" "Dockerfile.sdks" --build-arg BASE_IMAGE="${IMAGE_PREFIX}/base:latest"
   else
       # No local - let Dockerfile default pull from ghcr
       build_layer "sdks" "Dockerfile.sdks"
   fi
   ```

4. **Fix `cai refresh`** at `src/lib/update.sh:2228-2252`:
   - Currently `_cai_refresh()` always pulls `_cai_base_image()` (the runtime image `ghcr.io/novotnyllc/containai:latest`)
   - Add digest comparison: fetch GHCR manifest digest, compare with local RepoDigest
   - Only pull if digests differ; show "already up-to-date" when they match
   - This is about the runtime image, not build layers

5. **Context-aware local check**: Ensure `docker image inspect` uses the same context that the build will use (for buildx scenarios).

## Key context

- `_cai_base_image()` returns `ghcr.io/novotnyllc/containai:latest` (runtime image)
- `cai refresh` updates the runtime image, not build layers
- Build layers (`base`, `sdks`, `agents`) are different from the final runtime image
- Dockerfiles already have correct ghcr defaults in their ARG lines
- Only override defaults when we KNOW a local image exists in the current context
- Digest comparison can use: `docker manifest inspect` for remote, `docker image inspect --format '{{.RepoDigests}}'` for local

## Acceptance
- [ ] Default `IMAGE_PREFIX` changed to `ghcr.io/novotnyllc/containai`
- [ ] Help text and examples updated to show new default prefix
- [ ] `IMAGE_FULL` renamed to `IMAGE_AGENTS` in build.sh
- [ ] `--layer agents` works (validates correctly)
- [ ] `--layer full` produces helpful error or alias to `agents`
- [ ] Help text shows `--layer base|sdks|agents|all`
- [ ] `./src/build.sh` only passes `--build-arg BASE_IMAGE=...` when local image exists
- [ ] `./src/build.sh` only passes `--build-arg SDKS_IMAGE=...` when local image exists
- [ ] `./src/build.sh` only passes `--build-arg AGENTS_IMAGE=...` when local image exists
- [ ] `cai refresh` compares local digest with remote before pulling
- [ ] `cai refresh` shows "already up-to-date" when digests match
- [ ] `cai refresh` pulls only when digests differ
- [ ] Build still works when no local images exist (uses Dockerfile defaults)
- [ ] Build still works when local images exist (uses them)
- [ ] `--image-prefix` flag still works for custom registries
- [ ] Verbose mode shows which path was taken (local/remote default)
- [ ] Existing tests pass (`tests/integration/test-secure-engine.sh`)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
