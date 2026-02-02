# fn-32-2mq.9 Update install.sh and update flow for channel support

## Description

Modify `install.sh` and the `cai update` command to support channel-aware code distribution: stable channel checks out latest git tag, nightly channel tracks main branch.

**CAI_BRANCH vs CAI_CHANNEL Precedence:**
The existing `CAI_BRANCH` environment variable allows users to pin a specific git branch. The new `CAI_CHANNEL` controls stable vs nightly release channels.

**Precedence (highest to lowest):**
1. `CAI_BRANCH` - explicit branch override (power users, testing) - WINS over channel
2. `CAI_CHANNEL` - channel selection (stable/nightly)
3. Default: stable channel (checkout latest tag)

When `CAI_BRANCH` is set, channel logic is bypassed entirely. This preserves backward compatibility.

**Install.sh Changes:**

1. Add channel detection with branch precedence:
```bash
BRANCH="${CAI_BRANCH:-}"
CHANNEL="${CAI_CHANNEL:-stable}"
```

2. After clone, checkout based on precedence:
```bash
if [[ -n "$BRANCH" ]]; then
  # Explicit branch override - bypass channel logic
  git checkout "$BRANCH"
  info "Checked out branch: $BRANCH (CAI_BRANCH override)"
elif [[ "$CHANNEL" == "nightly" ]]; then
  # Nightly: stay on main branch
  git checkout main
  info "Checked out nightly channel (main branch)"
else
  # Stable: checkout latest semver tag
  latest_tag=$(git tag -l 'v*' | sort -V | tail -1)
  if [[ -n "$latest_tag" ]]; then
    git checkout "$latest_tag"
    info "Checked out stable release: $latest_tag"
  else
    warn "No release tags found, staying on main"
  fi
fi
```

3. Update messaging to show channel/branch:
```
[INFO] Installing ContainAI (channel: stable)
[INFO] Checked out stable release: v0.2.0
```

**Update Flow Changes (in src/lib/version.sh or update module):**

1. Read channel from config: `_cai_config_channel`
2. Check for branch override in env or config

3. Implement precedence-aware update:
```bash
_cai_update() {
  local branch="${CAI_BRANCH:-}"
  local channel
  channel="$(_cai_config_channel)"

  cd "$INSTALL_DIR"
  git fetch --tags

  if [[ -n "$branch" ]]; then
    # Explicit branch override
    git checkout "$branch"
    git pull origin "$branch"
    _cai_info "Updated branch: $branch (CAI_BRANCH override)"
  elif [[ "$channel" == "nightly" ]]; then
    git checkout main
    git pull origin main
    _cai_info "Updated to latest nightly ($(git rev-parse --short HEAD))"
  else
    local latest_tag
    latest_tag=$(git tag -l 'v*' | sort -V | tail -1)
    if [[ -n "$latest_tag" ]]; then
      git checkout "$latest_tag"
      _cai_info "Updated to stable release: $latest_tag"
    else
      _cai_warn "No release tags found"
    fi
  fi
}
```

**Tag Selection Logic:**
```bash
# Sort tags by semver (handles v0.1.0 vs v0.10.0 correctly)
latest_tag=$(git tag -l 'v*' | sort -V | tail -1)
```

**Edge Cases:**
- No tags exist yet: warn and stay on main
- Network failure during fetch: exit with error
- Dirty working tree: warn user, don't force checkout
- Invalid channel value: fall back to stable with warning

## Acceptance

- [ ] `install.sh` reads both `CAI_BRANCH` and `CAI_CHANNEL` environment variables
- [ ] `CAI_BRANCH` takes precedence over `CAI_CHANNEL` (branch wins)
- [ ] When `CAI_BRANCH` set: checkout that branch, bypass channel logic
- [ ] When `CAI_CHANNEL=nightly` (no branch): stay on/pull main
- [ ] When `CAI_CHANNEL=stable` or default (no branch): checkout latest tag
- [ ] Install messaging shows channel/branch being used
- [ ] `cai update` reads channel from config system
- [ ] `cai update` respects `CAI_BRANCH` env var over channel
- [ ] Stable update fetches tags and checks out latest
- [ ] Nightly update pulls latest main
- [ ] Tag selection uses `sort -V` for proper semver ordering
- [ ] Gracefully handles no tags (warns, stays on main)
- [ ] Network failure during update exits with error
- [ ] Warns if working tree is dirty before checkout
- [ ] Shows what changed (before/after version or commit)
- [ ] Backward compatible with existing `CAI_BRANCH` usage

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
