# fn-32-2mq.4 Create GitHub Release workflow

## Description

Create `.github/workflows/release.yml` to automatically create GitHub Releases after successful tag builds.

**Trigger Options:**
- Option A: `workflow_run` triggered after docker.yml completes on tags
- Option B: `push: tags: ['v*']` with explicit dependency check

Recommend Option B for simplicity (docker.yml runs in parallel, release.yml can check for image existence).

**Workflow Steps:**
1. Checkout repository at tag
2. Wait for docker image to be available (poll GHCR, max 10 min)
3. Generate release notes from commits since last tag
4. Create GitHub Release with:
   - Tag name: `v0.1.0`
   - Release name: `ContainAI v0.1.0`
   - Body: auto-generated notes
   - Mark as latest release (not pre-release)

**Release Notes Format:**
Use GitHub's auto-generated notes or `gh release create --generate-notes`.

## Acceptance

- [ ] Workflow file exists at `.github/workflows/release.yml`
- [ ] Triggers on push to tags `v*`
- [ ] Waits for docker image availability before creating release (or runs after docker.yml)
- [ ] Creates GitHub Release with correct tag name
- [ ] Uses auto-generated release notes
- [ ] Release is marked as "latest" (not draft, not pre-release)
- [ ] Has `contents: write` permission
- [ ] Handles v0.x releases correctly (no special pre-release marking)
- [ ] Release creation fails gracefully if tag doesn't exist

## Done summary
## Summary

Created `.github/workflows/release.yml` to automatically create GitHub Releases after tag pushes.

### Implementation Details

- **Trigger**: Push to tags matching `v*`
- **Permission**: `contents: write` for release creation
- **Docker Image Wait**: Polls GHCR API for up to 10 minutes (60 attempts × 10s) to ensure the Docker image is available before creating the release
- **Release Creation**: Uses `gh release create` with:
  - Title: "ContainAI vX.Y.Z"
  - Auto-generated release notes (`--generate-notes`)
  - Marked as latest release (`--latest`)
  - Not draft, not pre-release

### Key Features

1. Runs independently of docker.yml (both trigger on tag push, run in parallel)
2. Gracefully handles image not being ready (warns but proceeds)
3. Uses gh CLI for release creation (simpler than actions/create-release)
4. Properly handles v0.x releases (no special pre-release marking)

### Files Changed

- `.github/workflows/release.yml` (new)
## Evidence
- Commits:
- Tests:
- PRs:
