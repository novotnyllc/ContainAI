# fn-32-2mq.3 Modify docker.yml for channel tagging

## Description

Update `.github/workflows/docker.yml` to implement correct tag semantics for stable vs nightly channels, including layer images and cron schedule for nightly builds.

**Current Behavior (incorrect):**
- `latest` tag produced on main branch push (via `enable={{is_default_branch}}`)
- No `nightly` tags at all
- No scheduled builds
- Layer tags always use `latest` regardless of build type

**Target Behavior:**
- `latest` tag ONLY from tag pushes (`refs/tags/v*`)
- Main branch pushes produce `nightly` and `nightly-YYYYMMDD` tags
- Scheduled cron at 2am UTC triggers nightly builds
- Semver tags (0.1.0, 0.1) only from tag pushes
- Layer tags (base/sdks/agents) use `:latest` for stable, `:nightly` for main/schedule

**Changes Required:**

1. Add cron schedule trigger:
```yaml
on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 2 * * *'  # 2am UTC daily
```

2. Add step to compute nightly date:
```yaml
- name: Get build date
  id: date
  run: echo "value=$(date +%Y%m%d)" >> $GITHUB_OUTPUT
```

3. Update `tag_suffix` in build strategy to handle schedule:
```yaml
# For non-PR builds, set tag_suffix based on ref
if [[ "${{ github.ref }}" == refs/tags/v* ]]; then
  echo "tag_suffix=latest" >> $GITHUB_OUTPUT
else
  # Main branch push OR scheduled run
  echo "tag_suffix=nightly" >> $GITHUB_OUTPUT
fi
```

4. Modify metadata-action tags section:
```yaml
tags: |
  # latest ONLY for tagged releases
  type=raw,value=latest,enable=${{ startsWith(github.ref, 'refs/tags/v') }}
  # Semver for tags only
  type=semver,pattern={{version}},enable=${{ startsWith(github.ref, 'refs/tags/v') }}
  type=semver,pattern={{major}}.{{minor}},enable=${{ startsWith(github.ref, 'refs/tags/v') }}
  type=semver,pattern={{major}},enable=${{ startsWith(github.ref, 'refs/tags/v') && !startsWith(github.ref, 'refs/tags/v0.') }}
  # Nightly for main branch and schedule
  type=raw,value=nightly,enable=${{ github.ref == 'refs/heads/main' || github.event_name == 'schedule' }}
  type=raw,value=nightly-${{ steps.date.outputs.value }},enable=${{ github.ref == 'refs/heads/main' || github.event_name == 'schedule' }}
  # SHA for all builds
  type=sha,prefix=sha-
```

5. Add concurrency to prevent parallel builds:
```yaml
concurrency:
  group: docker-${{ github.ref }}
  cancel-in-progress: true
```

## Acceptance

- [ ] `latest` tag only produced for `refs/tags/v*` pushes
- [ ] Semver tags (0.1.0, 0.1) only produced for `refs/tags/v*` pushes
- [ ] Main branch push produces `nightly` tag
- [ ] Main branch push produces `nightly-YYYYMMDD` tag using step output
- [ ] Cron schedule `0 2 * * *` added for nightly builds
- [ ] Scheduled builds produce `nightly` and `nightly-YYYYMMDD` tags
- [ ] SHA tags (sha-abc123) produced for all builds
- [ ] Major-only tag still disabled for v0.x releases
- [ ] Layer tags (base, sdks, agents) use `:latest` for tag builds
- [ ] Layer tags (base, sdks, agents) use `:nightly` for main/schedule builds
- [ ] Concurrency group prevents parallel docker builds for same ref
- [ ] PR builds still work (amd64 only, no push)
- [ ] Existing layer caching preserved

## Done summary
# Task fn-32-2mq.3 Summary: Modify docker.yml for channel tagging

## Changes Made

Updated `.github/workflows/docker.yml` to implement correct tag semantics for stable vs nightly channels.

### 1. Added schedule trigger
- Cron schedule `0 2 * * *` (2am UTC daily) for nightly builds

### 2. Added concurrency control
- `concurrency.group: docker-${{ github.ref }}` prevents parallel builds for same ref
- `cancel-in-progress: true` to stop older runs when new one starts

### 3. Added build date step
- New step `Get build date` outputs `YYYYMMDD` format for nightly tags

### 4. Updated build strategy for layer tags
- Tag builds (`refs/tags/v*`): `tag_suffix=latest`
- Main branch/schedule builds: `tag_suffix=nightly`
- Layer images (base/sdks/agents) now correctly tagged per channel

### 5. Updated metadata-action tags
- `latest` tag ONLY for `refs/tags/v*` pushes (not main branch)
- Semver tags (`0.1.0`, `0.1`) ONLY for tag pushes
- Major-only tag (`1`) disabled for v0.x releases
- `nightly` tag for main branch and scheduled builds
- `nightly-YYYYMMDD` tag for main branch and scheduled builds
- SHA tags (`sha-abc123`) for all builds

## Acceptance Criteria Met

- [x] `latest` tag only produced for `refs/tags/v*` pushes
- [x] Semver tags (0.1.0, 0.1) only produced for `refs/tags/v*` pushes
- [x] Main branch push produces `nightly` tag
- [x] Main branch push produces `nightly-YYYYMMDD` tag using step output
- [x] Cron schedule `0 2 * * *` added for nightly builds
- [x] Scheduled builds produce `nightly` and `nightly-YYYYMMDD` tags
- [x] SHA tags (sha-abc123) produced for all builds
- [x] Major-only tag still disabled for v0.x releases
- [x] Layer tags (base, sdks, agents) use `:latest` for tag builds
- [x] Layer tags (base, sdks, agents) use `:nightly` for main/schedule builds
- [x] Concurrency group prevents parallel docker builds for same ref
- [x] PR builds still work (amd64 only, no push)
- [x] Existing layer caching preserved
## Evidence
- Commits:
- Tests:
- PRs:
