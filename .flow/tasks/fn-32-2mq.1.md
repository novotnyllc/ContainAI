# fn-32-2mq.1 Create release-cut GitHub Action

## Description

Create `.github/workflows/release-cut.yml` workflow that handles version bumping and tag creation. This workflow is manually triggered (workflow_dispatch) and is the entry point for creating new releases.

**Key Design Decisions:**
- Separates version management from image building (avoids recursion)
- Only runs on workflow_dispatch (not on push)
- Creates annotated git tags (not lightweight)
- Pushes tag which triggers docker.yml for image builds

**Workflow Steps:**
1. Accept bump type input (major/minor/patch)
2. Checkout with full history (for tag context)
3. Run `scripts/bump-version.sh <type>` to update VERSION
4. Commit VERSION change with message: `chore(release): bump version to X.Y.Z`
5. Create annotated tag: `git tag -a v$VERSION -m "Release v$VERSION"`
6. Push commit and tag: `git push && git push --tags`

**Required Permissions:**
- `contents: write` (for push and tag creation)

**Guards:**
- `if: github.ref == 'refs/heads/main'` - only run on main branch
- Concurrency group to prevent parallel release cuts

## Acceptance

- [ ] Workflow file exists at `.github/workflows/release-cut.yml`
- [ ] Accepts `bump_type` input with choices: major, minor, patch
- [ ] Correctly calls `scripts/bump-version.sh` with bump type
- [ ] Commits VERSION change with conventional commit message
- [ ] Creates annotated git tag in `v0.1.0` format
- [ ] Pushes both commit and tag to origin
- [ ] Has `contents: write` permission
- [ ] Includes `if: github.ref == 'refs/heads/main'` guard
- [ ] Uses concurrency group `release-cut` to prevent parallel runs
- [ ] Does NOT trigger image build directly (relies on docker.yml tag trigger)

## Done summary
## Summary

Created `.github/workflows/release-cut.yml` GitHub Action workflow that handles version bumping and tag creation for ContainAI releases.

### Key Features

- **Manual trigger only**: Uses `workflow_dispatch` with `bump_type` input (major/minor/patch choices)
- **Main branch guard**: `if: github.ref == 'refs/heads/main'` ensures only runs on main
- **Concurrency control**: `concurrency.group: release-cut` prevents parallel release cuts
- **Full git history**: `fetch-depth: 0` for proper tag context
- **Annotated tags**: Uses `git tag -a` for proper release tags
- **Conventional commits**: Commit message follows `chore(release): bump version to X.Y.Z` format
- **Separate concerns**: Does NOT build images directly; pushing the tag triggers docker.yml

### Workflow Steps

1. Checkout with full history
2. Configure git user for commits
3. Run `scripts/bump-version.sh <type>` to update VERSION
4. Commit VERSION change with conventional message
5. Create annotated tag `v<version>`
6. Push commit and tag to trigger docker.yml

### Permissions

- `contents: write` for pushing commits and creating tags
## Evidence
- Commits:
- Tests:
- PRs:
