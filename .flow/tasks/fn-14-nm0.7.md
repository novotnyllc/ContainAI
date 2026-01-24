# fn-14-nm0.7 Update cai uninstall to remove containai-docker context

## Description
Update `cai uninstall` to properly remove the `containai-docker` context that we actually create during setup. Currently it only removes `containai-secure` and `docker-containai` but misses our actual context name.

**Size:** S
**Files:** `src/lib/uninstall.sh`

## Current State

`uninstall.sh:64` has:
```bash
_CAI_UNINSTALL_CONTEXTS=("containai-secure" "docker-containai")
```

But setup creates `containai-docker` context (defined in `docker.sh:308`):
```bash
_CAI_CONTAINAI_DOCKER_CONTEXT="containai-docker"
```

## Approach

1. Update `_CAI_UNINSTALL_CONTEXTS` to include `containai-docker`
2. Better: Use the constant from `docker.sh` instead of hardcoding
3. Keep `containai-secure` for legacy cleanup
4. Update help text and dry-run output to show correct context name

**Pattern to follow:** Import constant from `docker.sh`:
```bash
_CAI_UNINSTALL_CONTEXTS=("$_CAI_CONTAINAI_DOCKER_CONTEXT" "containai-secure" "docker-containai")
```

## Key Context

- Constant is defined in `src/lib/docker.sh:308`: `_CAI_CONTAINAI_DOCKER_CONTEXT="containai-docker"`
- Uninstall already sources docker.sh (via containai.sh sourcing order)
- The array at `uninstall.sh:64` needs updating
## Acceptance
- [ ] `_CAI_UNINSTALL_CONTEXTS` includes `containai-docker`
- [ ] Uses `$_CAI_CONTAINAI_DOCKER_CONTEXT` constant (not hardcoded)
- [ ] `cai uninstall --dry-run` shows `containai-docker` context removal
- [ ] Legacy contexts `containai-secure` and `docker-containai` still cleaned up
- [ ] Help text lists `containai-docker` as context that will be removed
- [ ] `shellcheck -x src/lib/uninstall.sh` passes
## Done summary
## Summary

Updated `cai uninstall` to properly remove the `containai-docker` context that is actually created during setup.

### Changes Made

1. **Updated `_CAI_UNINSTALL_CONTEXTS` array** (line 66): Now uses the `$_CAI_CONTAINAI_DOCKER_CONTEXT` constant from `docker.sh` instead of hardcoding, with legacy contexts for backward compatibility.

2. **Updated header comment** (line 16): Reflects the current context name being removed.

3. **Updated dry-run/info output** (line 491): Shows `containai-docker, containai-secure (legacy)` instead of the old context names.

4. **Updated help text** (line 599): Lists the correct context names in the "What Gets Removed" section.

All changes pass shellcheck and the dry-run output correctly shows the `containai-docker` context.
## Evidence
- Commits: a19c4ef
- Tests: shellcheck -x src/lib/uninstall.sh, cai uninstall --dry-run, cai uninstall --help
- PRs:
- Review: SHIP via flowctl codex impl-review
