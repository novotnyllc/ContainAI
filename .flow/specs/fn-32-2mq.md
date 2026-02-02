# fn-32-2mq Release Pipeline & Image Management

## Overview

Define and implement the complete release story for ContainAI. This includes automated versioning, image tagging, release channels (stable/nightly), and improved user experience around image management.

**Key Goals:**
1. Automated version bumping and tagging via GitHub Actions
2. Stable/Nightly release channels for both code and images
3. Smart image pulling (show size, date, prompt user)
4. Image freshness checks with `cai --refresh` suggestion

## Scope

### In Scope
- GitHub Action for version increment, tagging, and release creation
- Nightly builds via cron schedule in docker.yml (not separate workflow)
- Stable vs Nightly release channels (applies to both code and images)
- Image pull UX improvements:
  - Prompt to pull when no local base image
  - Show image size and date before pulling
  - Check for newer images and suggest `cai --refresh`
- Modify docker.yml to produce `latest` only from tags (not main branch)
- VERSION file management
- Template system updates for channel-aware base images
- Update install.sh and cai update for channel-aware code distribution

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

**Stable Channel (default):**
- Built from tagged releases (v*) only
- Docker tags: `latest`, `0.1.0`, `0.1` (no v prefix, semver-docker convention)
- Major tag (e.g., `1`) enabled only for v1.0.0+
- Code installs track latest git tag (checkout, not branch)
- Used by default in `cai` commands

**Nightly Channel (opt-in):**
- Built from main branch on schedule (cron at 2am UTC) and on push
- Docker tags: `nightly`, `nightly-YYYYMMDD`
- Code installs track `main` branch
- Opt-in via config `[image].channel = "nightly"` or `--channel nightly` CLI flag
- May have breaking changes, not guaranteed stable

### Channel Selection Precedence

1. CLI flag: `--channel nightly` (highest priority)
2. Environment: `CONTAINAI_CHANNEL=nightly`
3. Config file: `[image].channel = "nightly"`
4. Default: `stable`

### Docker Tag Strategy

Docker tags use numeric semver without `v` prefix (docker convention):
- Tagged release `v0.2.0` → docker tags: `latest`, `0.2.0`, `0.2`, `sha-abc123`
- Nightly build → docker tags: `nightly`, `nightly-20260202`, `sha-def456`

The major-only tag (e.g., `:1`) is disabled for v0.x releases per existing docker.yml logic.

**Layer Tags (base/sdks/agents):**
- Stable builds: `base:latest`, `sdks:latest`, `agents:latest`
- Nightly builds: `base:nightly`, `sdks:nightly`, `agents:nightly`
- This ensures layer tags don't mix between channels.

### GitHub Actions Workflow Design

Split responsibilities to avoid recursion and ensure clean separation:

**1. release-cut.yml (workflow_dispatch only):**
- Input: bump type (major/minor/patch)
- Bumps VERSION file, commits, creates annotated git tag, pushes
- Does NOT build images (triggers docker.yml via tag push)
- Requires `contents: write` permission

**2. docker.yml (modified):**
- Triggers:
  - `push: tags: ['v*']` → stable builds
  - `push: branches: [main]` → nightly builds
  - `schedule: cron: '0 2 * * *'` → scheduled nightly builds (2am UTC daily)
- Stable builds (from tag): produce `latest`, semver tags; layer tags use `latest`
- Main/schedule builds: produce `nightly`, `nightly-YYYYMMDD`; layer tags use `nightly`
- Uses concurrency groups to prevent parallel builds
- Nightly date tag uses step output: `echo "date=$(date +%Y%m%d)" >> $GITHUB_OUTPUT`

**3. release.yml (push to tags v* only):**
- Creates GitHub Release with auto-generated notes
- Runs after docker.yml succeeds (via workflow_run or needs)
- Requires `contents: write` permission

### Image Pull UX

The freshness check applies to the **base image** referenced by templates (e.g., `ghcr.io/novotnyllc/containai:latest`), not the locally-built template image. Users who build custom templates should understand freshness refers to the upstream base.

**Hook Point:** The image pull prompt occurs in `_cai_build_template()` in `src/lib/template.sh`, just before the template build pulls the base image. This ensures the correct Docker context is used.

**No Local Base Image:**
```
$ cai shell
[NOTICE] No local ContainAI base image found.
         Image: ghcr.io/novotnyllc/containai:latest
         Size: ~2.1 GB (compressed)
         Published: 2026-01-15

Pull image? [Y/n]:
```

**Newer Base Image Available:**
```
$ cai shell
[NOTICE] A newer ContainAI base image is available.
         Local: 0.1.0 (2026-01-10)
         Remote: 0.2.0 (2026-01-15)

         Run 'cai --refresh' to update.

Starting container with current image...
```

**Important**: The freshness check uses `[NOTICE]` level (always visible, not gated by `--verbose`). This requires adding `_cai_notice()` to core.sh that prints `[NOTICE]` unconditionally to stderr (like `_cai_warn` but semantically informational).

### Image Metadata Implementation

Query GHCR registry for image metadata using the Docker Registry HTTP API v2.

**Authentication:**
- Attempt anonymous token first (public repo)
- If 401/403, print `[NOTICE] Cannot check for updates (authentication required)` and continue
- Do NOT block on auth failure

**Digest Comparison Strategy:**
For multi-arch images, `RepoDigests` contains the **manifest list digest** (not platform-specific). Therefore:
- Fetch the manifest list digest from the registry for the tag
- Compare against local `docker image inspect --format '{{index .RepoDigests 0}}'`
- This compares like-for-like (both manifest list digests)
- If digests differ, a newer version is available

**Timeouts & Caching:**
- Hard timeout: 2 seconds for registry calls
- Cache: per-tag results for 60 minutes in `~/.config/containai/cache/registry/`
- On timeout/network error: show `[NOTICE] Cannot check for updates (network error)` and proceed
- On parse error: silently skip (internal issue, not user-actionable)

**Metadata Sources:**
- Version: `org.opencontainers.image.version` label (already in Dockerfiles)
- Created date: `org.opencontainers.image.created` label
- Digest: manifest list digest for comparison
- Size: sum of layer sizes from manifest (approximate compressed)

**JSON Parsing:**
Use Python (already required dependency) instead of jq:
```bash
python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))"
```

### Channel Configuration & Templates

Config option for release channel (uses existing config system):
```toml
# ~/.config/containai/config.toml (or workspace override)
[image]
channel = "stable"  # or "nightly"
```

**Integration with Existing Config:**
- Add `channel` to `_containai_parse_config` in `src/lib/config.sh`
- Uses existing pattern: `python3 "$script_dir/parse-toml.py" --file "$config_file" --json`
- Store in new global: `_CAI_IMAGE_CHANNEL`
- Helper `_cai_config_channel()` resolves precedence (CLI > env > global > default)
- Follows existing XDG paths and workspace config precedence
- Invalid values log warning and fall back to stable

**Template Integration:**
- Templates live in `~/.config/containai/templates/<name>/Dockerfile`
- Default template uses `ARG BASE_IMAGE=ghcr.io/novotnyllc/containai:latest`
- `_cai_build_template` passes `--build-arg BASE_IMAGE=$(_cai_base_image)` based on channel

**Existing Template Migration:**
- Templates installed before this change have hardcoded `FROM ghcr.io/novotnyllc/containai:latest`
- `cai doctor` should detect this and warn: "Template uses hardcoded base image. Run `cai template upgrade` to enable channel selection."
- `cai template upgrade` (new command) rewrites the FROM line to use ARG pattern

### Code Distribution Model

**CAI_BRANCH vs CAI_CHANNEL Precedence:**
The existing `CAI_BRANCH` environment variable allows users to pin a specific git branch (e.g., for testing a feature branch). The new `CAI_CHANNEL` controls stable vs nightly release channels.

**Precedence rules (highest to lowest):**
1. `CAI_BRANCH` - explicit branch override (power users, testing)
2. `CAI_CHANNEL` - channel selection (stable/nightly)
3. Default: stable channel (checkout latest tag)

When `CAI_BRANCH` is set, it takes full precedence and channel logic is bypassed. This preserves backward compatibility for users who pin specific branches.

**Behavior Matrix:**
| CAI_BRANCH | CAI_CHANNEL | Behavior |
|------------|-------------|----------|
| set        | (any)       | Checkout specified branch (branch wins) |
| unset      | nightly     | Checkout/pull `main` branch |
| unset      | stable      | Checkout latest `v*` tag |
| unset      | unset       | Checkout latest `v*` tag (default=stable) |

**Stable installs (default, no CAI_BRANCH):**
- `install.sh` clones repo, then checks out latest `v*` tag
- `cai update` fetches tags, checks out latest `v*` tag
- Ensures code matches the stable image version

**Nightly installs (CAI_CHANNEL=nightly, no CAI_BRANCH):**
- `install.sh` clones repo, stays on `main` branch
- `cai update` pulls latest `main`
- Accepts that nightly code may have breaking changes

**Branch override (CAI_BRANCH set):**
- `install.sh` clones repo, checks out specified branch
- `cai update` pulls the pinned branch
- Channel setting is ignored when branch is explicitly set

**Tag Selection Logic:**
```bash
# Get latest semver tag
latest_tag=$(git tag -l 'v*' | sort -V | tail -1)
git checkout "$latest_tag"
```

## Tasks

### fn-32-2mq.1: Create release-cut GitHub Action
New `release-cut.yml` workflow for version management.

### fn-32-2mq.2: Implement version bump script
Shell script for semver increment with validation.

### fn-32-2mq.3: Modify docker.yml for channel tagging
Update existing workflow to produce correct tags per channel, add cron schedule.

### fn-32-2mq.4: Create GitHub Release workflow
New `release.yml` to create releases after successful tag builds.

### fn-32-2mq.5: Implement image pull prompt
Prompt and metadata display when base image missing (in template.sh).

### fn-32-2mq.6: Implement image freshness check
Check for newer base image on container start (manifest list digest comparison).

### fn-32-2mq.7: Implement cai --refresh command
Pull latest base image and optionally rebuild template (context-aware).

### fn-32-2mq.8: Add channel configuration
Config option, CLI flag, and template integration for channel selection.

### fn-32-2mq.9: Update install.sh and update flow for channel support
Modify install.sh and cai update to checkout tags (stable) or main (nightly).

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

# Check registry metadata (future implementation)
curl -s "https://ghcr.io/v2/novotnyllc/containai/manifests/latest" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json"
```

## Acceptance

- [ ] `release-cut.yml` bumps VERSION, creates tag, pushes (no direct image build)
- [ ] Git tags follow `v0.1.0` format; docker tags follow `0.1.0` format
- [ ] `latest` docker tag ONLY from tagged releases (not main branch)
- [ ] `nightly`/`nightly-YYYYMMDD` tags from main branch builds
- [ ] Cron schedule triggers nightly builds at 2am UTC
- [ ] Layer tags (base/sdks/agents) use `latest` for stable, `nightly` for main
- [ ] GitHub Releases created with auto-generated notes
- [ ] `cai shell` prompts to pull when no local base image
- [ ] Image size and date shown before pull (from OCI labels)
- [ ] Freshness check shows `[NOTICE]` (always visible) when newer available
- [ ] Auth failures show `[NOTICE] Cannot check for updates (authentication required)`
- [ ] Network errors show `[NOTICE] Cannot check for updates (network error)`
- [ ] Digest comparison uses manifest list digest (like-for-like)
- [ ] `cai --refresh` pulls latest base and optionally rebuilds template
- [ ] `cai --refresh` passes Docker context to `_cai_build_template`
- [ ] `--channel nightly` CLI flag overrides config
- [ ] Channel precedence: CLI > env > config > default
- [ ] `CAI_BRANCH` takes precedence over `CAI_CHANNEL` (branch wins)
- [ ] Channel stored in `_CAI_IMAGE_CHANNEL` global after config parsing
- [ ] Channel configurable via `[image].channel` in existing config system
- [ ] Templates use `ARG BASE_IMAGE` pattern for channel selection
- [ ] `cai doctor` detects hardcoded template base images
- [ ] Registry API calls timeout at 2s, cache for 60min in `~/.config/containai/cache/registry/`
- [ ] JSON parsing uses Python (not jq)
- [ ] `install.sh` checks out latest tag for stable channel
- [ ] `install.sh` respects `CAI_BRANCH` over `CAI_CHANNEL`
- [ ] `cai update` respects channel for code updates

## Dependencies

- **fn-36-rb7**: CLI UX consistency (provides `--refresh` semantics)
- **fn-31-gib**: Import reliability (test suite helps validate releases)
- **fn-33-lp4**: User templates (image build flow, template upgrade mechanism)
- **fn-34-fk5**: One-shot execution (container lifecycle)
- Existing: `.github/workflows/docker.yml`

## References

- Current docker.yml: `.github/workflows/docker.yml`
- VERSION file: `VERSION`
- Docker Registry API v2: https://docs.docker.com/registry/spec/api/
- GHCR Token Auth: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic
- OCI Image Spec (labels): https://github.com/opencontainers/image-spec/blob/main/annotations.md
- Semantic Versioning: https://semver.org/
