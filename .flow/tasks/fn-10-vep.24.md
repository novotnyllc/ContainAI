# fn-10-vep.24 Set up GitHub Container Registry publishing

## Description
Set up GitHub Container Registry (GHCR) publishing with GitHub Actions for multi-arch images.

**Size:** M
**Files:**
- `.github/workflows/docker.yml` (new)
- `src/docker/Dockerfile` (add labels)

## Approach

1. Create GitHub Actions workflow for:
   - Build on push to main
   - Build on tag for releases
   - Multi-arch: amd64, arm64
2. Use docker/build-push-action
3. Add OCI labels to Dockerfile
4. Configure GHCR authentication

## Key context

- Registry: ghcr.io/novotnyllc/containai
- Tags: latest, version (from VERSION file or git tag)
- Platforms: linux/amd64, linux/arm64
## Acceptance
- [ ] GitHub Actions workflow created
- [ ] Builds trigger on push to main
- [ ] Builds trigger on version tags
- [ ] Multi-arch images (amd64, arm64)
- [ ] Images published to ghcr.io
- [ ] OCI labels present in image
- [ ] README badge for build status
## Done summary
Set up GitHub Actions workflow for multi-arch Docker builds published to ghcr.io/novotnyllc/containai, with OCI labels in Dockerfile and build status badge in README.
## Evidence
- Commits: 362667c, 1fd0d9a
- Tests: workflow file syntax validation
- PRs:
