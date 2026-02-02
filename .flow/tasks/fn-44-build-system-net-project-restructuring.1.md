# fn-44-build-system-net-project-restructuring.1 Fix Docker build image prefix and local fallback

## Description
Fix the Docker build to use correct image prefix and add local image fallback before pulling from registry - for BOTH `build.sh` AND `cai update`.

**Size:** M
**Files:**
- `src/build.sh`
- `src/lib/update.sh`

## Approach

1. **Fix image prefix**: The default `--image-prefix containai` resolves to `docker.io/containai/` which doesn't exist. Change default to `ghcr.io/novotnyllc/containai` or make registry explicit.

2. **Add local image fallback to build.sh**: Before pulling from registry, check if image exists locally using the pattern from `tests/integration/test-dind.sh:121-128`:
   ```bash
   if docker image inspect "$IMAGE" >/dev/null 2>&1; then
       # Use local image
   elif docker pull "$REGISTRY/$IMAGE" 2>/dev/null; then
       # Use pulled image
   else
       # Build from scratch
   fi
   ```

3. **Add local image fallback to cai update**: The `_cai_refresh_pull_base()` at `src/lib/update.sh:2248` always pulls. Add the same cascade pattern so it checks local first.

4. **Update layer build functions** at `src/build.sh:470-532` to use this cascade pattern.

## Key context

- Build uses buildx with `--load` for single-platform (line 349-352)
- Layer builds: base -> sdks -> agents -> final (line 470-532)
- `cai update` has `--rebuild` flag that rebuilds default template
- Each Dockerfile has ARG for upstream image (e.g., `Dockerfile.sdks:15` has `BASE_IMAGE` ARG)
## Approach

1. **Fix image prefix**: The default `--image-prefix containai` resolves to `docker.io/containai/` which doesn't exist. Change default to `ghcr.io/novotnyllc/containai` or make registry explicit.

2. **Add local image fallback**: Before pulling from registry, check if image exists locally using the pattern from `tests/integration/test-dind.sh:121-128`:
   ```bash
   if docker image inspect "$IMAGE" >/dev/null 2>&1; then
       # Use local image
   elif docker pull "$REGISTRY/$IMAGE" 2>/dev/null; then
       # Use pulled image
   else
       # Build from scratch
   fi
   ```

3. **Update layer build functions** at `src/build.sh:470-532` to use this cascade pattern.

## Key context

- Build uses buildx with `--load` for single-platform (line 349-352)
- Layer builds: base -> sdks -> agents -> final (line 470-532)
- Each Dockerfile has ARG for upstream image (e.g., `Dockerfile.sdks:15` has `BASE_IMAGE` ARG)
## Acceptance
- [ ] `./src/build.sh` without arguments uses correct registry prefix
- [ ] `./src/build.sh` uses existing local images without pulling
- [ ] `cai update` uses existing local images without pulling
- [ ] Build/update falls back to registry pull if local image missing
- [ ] Build/update falls back to building from scratch if pull fails
- [ ] `--image-prefix` flag still works for custom registries
- [ ] Verbose mode shows which path was taken (local/pull/build)
- [ ] Existing tests pass (`tests/integration/test-secure-engine.sh`)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
