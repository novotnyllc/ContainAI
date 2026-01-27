# fn-29-fv0.6 Update sysbox download URLs to new ContainAI release

## Description
Update sysbox download URLs to use the new ContainAI GitHub release.

**Size:** S
**Files:** `src/lib/setup.sh`, `src/container/Dockerfile.base`

## New URLs

```
https://github.com/novotnyllc/ContainAI/releases/download/sysbox-build-20260127-10/sysbox-ce_0.6.7+containai.20260127.linux_amd64.deb
https://github.com/novotnyllc/ContainAI/releases/download/sysbox-build-20260127-10/sysbox-ce_0.6.7+containai.20260127.linux_arm64.deb
```

## Changes

1. Update `_CAI_SYSBOX_CONTAINAI_TAG` at `setup.sh:463-465`:
   - Change from current value to `sysbox-build-20260127-10`

2. Version is derived from GitHub asset filename in `_cai_resolve_sysbox_download_url()`:
   - **No separate `_CAI_SYSBOX_CONTAINAI_VERSION` constant exists** - version is parsed from the filename
   - Only add a version constant if there's a concrete need (e.g., offline install or deterministic upgrade checks)

3. Update Dockerfile.base if it has hardcoded sysbox download URLs

4. Verify `_cai_resolve_sysbox_download_url()` at `setup.sh:650-780` builds correct URLs from the tag

## Key context

- The upstream nestybox fallback was removed in commit 2153301
- URL format: `https://github.com/novotnyllc/ContainAI/releases/download/${TAG}/sysbox-ce_${VERSION}.linux_${ARCH}.deb`
- Architecture is `amd64` or `arm64`
## Acceptance
- [ ] `cai setup` downloads sysbox from new ContainAI release URL
- [ ] Both amd64 and arm64 architectures use correct URLs
- [ ] Dockerfile.base uses same URLs (if applicable)
- [ ] Upgrade detection for sysbox works properly. Newer versions replace older versions.
## Done summary
Updated sysbox download URLs to use the new ContainAI GitHub release sysbox-build-20260127-10. Changed the pinned tag constant and updated example comments to reflect the new release date (20260127). Both amd64 and arm64 architectures are supported through the GitHub API-driven URL resolution.
## Evidence
- Commits: 7599b1903ef0edbdb3fa500e60b464e06eb7a25d, 2c6b62a745574438195f8fd014b1396f32246ef8, 17d677bc9697076ad5559f4b604e5229c8bf492a
- Tests: shellcheck -x src/lib/setup.sh, curl -sI (verified URLs accessible)
- PRs:
