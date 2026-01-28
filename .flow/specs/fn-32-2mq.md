# fn-32-2mq Release Pipeline & Image Management

## Overview

Define and implement the complete release story for ContainAI. This includes automated versioning, image tagging, release channels (stable/nightly), and improved user experience around image management.

**Key Goals:**
1. Automated version bumping and tagging via GitHub Actions
2. Stable/Nightly release channels
3. Smart image pulling (show size, date, prompt user)
4. Image freshness checks with `cai --refresh` suggestion

## Scope

### In Scope
- GitHub Action for version increment, tagging, and branching
- Stable vs Nightly build channels
- Image pull UX improvements:
  - Prompt to pull when no local image
  - Show image size and date before pulling
  - Check for newer images and suggest `cai --refresh`
- Enhance docker.yml workflow for full automation
- VERSION file management

### Out of Scope
- Multi-registry support (only GHCR for now)
- Signed images/SBOM (future enhancement)
- Automatic rollback mechanisms

## Approach

### Version Strategy

Use semantic versioning (MAJOR.MINOR.PATCH):
- **MAJOR**: Breaking changes to CLI or config format
- **MINOR**: New features, new agent support
- **PATCH**: Bug fixes, security patches

Version sources:
- `VERSION` file in repo root (single source of truth)
- Git tags for releases (v0.1.0, v0.2.0, etc.)

### Release Channels

**Stable Channel:**
- Built from tagged releases (v*)
- Images tagged: `latest`, `v0.1.0`, `v0.1`, `v0`
- Used by default in `cai` commands
- Tested and documented

**Nightly Channel:**
- Built from main branch nightly
- Images tagged: `nightly`, `nightly-YYYYMMDD`
- Opt-in via config or `--channel nightly`
- May have breaking changes

### GitHub Actions Workflow

```yaml
# New workflow: release.yml
name: Release

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      bump_type:
        description: 'Version bump type'
        required: true
        default: 'patch'
        type: choice
        options: [major, minor, patch]

jobs:
  version:
    # Bump VERSION file, create tag, push

  build:
    # Build and push images to GHCR

  release:
    # Create GitHub Release with notes
```

### Image Pull UX

**No Local Image:**
```
$ cai shell
[INFO] No local ContainAI image found.
       Image: ghcr.io/novotnyllc/containai:latest
       Size: 2.1 GB (compressed)
       Published: 2026-01-15

Pull image? [Y/n]:
```

**Newer Image Available:**
```
$ cai shell
[INFO] A newer ContainAI image is available.
       Local: v0.1.0 (2026-01-10)
       Remote: v0.2.0 (2026-01-15)

       Run 'cai --refresh' to update.

Starting container with current image...
```

Note: The freshness check is INFO level, not a warning. It shouldn't block the user.

### Image Metadata

Query image metadata via Docker Registry API:
- Image size (compressed)
- Created date
- Version label
- Digest for comparison

## Tasks

### fn-32-2mq.1: Create release GitHub Action
New `release.yml` workflow that:
- Accepts manual trigger with version bump type
- Bumps VERSION file
- Creates and pushes git tag
- Triggers image build

### fn-32-2mq.2: Implement version bump script
Shell script or action to:
- Read current VERSION
- Increment based on bump type
- Write new VERSION
- Commit change

### fn-32-2mq.3: Add nightly build workflow
New `nightly.yml` or cron in existing workflow:
- Build from main branch
- Tag images as `nightly`, `nightly-YYYYMMDD`
- Run at 2am UTC daily

### fn-32-2mq.4: Create GitHub Release automatically
After successful build from tag:
- Create GitHub Release
- Auto-generate release notes from commits
- Attach checksums if applicable

### fn-32-2mq.5: Implement image pull prompt
When no local image:
- Query registry for image metadata
- Display size and date
- Prompt user before pulling
- Pull and retry command

### fn-32-2mq.6: Implement image freshness check
On container start:
- Compare local image digest with remote
- If newer available, show INFO message
- Suggest `cai --refresh` command
- Don't block or warn

### fn-32-2mq.7: Implement cai --refresh command
New flag or subcommand:
- Pull latest image for configured channel
- Optionally recreate running containers
- Show what changed (version diff)

### fn-32-2mq.8: Add channel configuration
Config option for release channel:
```toml
[image]
channel = "stable"  # or "nightly"
```

## Quick commands

```bash
# Current workflow test
./src/build.sh --image-prefix containai

# Check VERSION file
cat VERSION

# List remote tags
gh api /orgs/novotnyllc/packages/container/containai/versions --jq '.[].metadata.container.tags[]'

# Manual version bump (future)
./scripts/bump-version.sh patch
```

## Acceptance

- [ ] GitHub Action bumps VERSION file correctly
- [ ] Git tags created automatically (v0.1.0 format)
- [ ] GitHub Releases created with notes
- [ ] Nightly builds run and tag correctly
- [ ] `cai shell` prompts to pull when no local image
- [ ] Image size and date shown before pull
- [ ] Freshness check shows INFO when newer available
- [ ] `cai --refresh` pulls latest and optionally recreates containers
- [ ] Channel configurable via config file

## Dependencies

- **fn-36-rb7**: CLI UX consistency (provides `--refresh` semantics)
- **fn-31-gib**: Import reliability (test suite helps validate releases)
- **fn-33-lp4**: User templates (image build flow)
- **fn-34-fk5**: One-shot execution (container lifecycle)
- Existing: `.github/workflows/docker.yml`

## References

- Current docker.yml: `.github/workflows/docker.yml`
- VERSION file: `VERSION`
- Docker Registry API: https://docs.docker.com/registry/spec/api/
- GitHub Packages API: https://docs.github.com/en/rest/packages
- Semantic Versioning: https://semver.org/
