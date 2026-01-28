# fn-30-x9f.2 Fix Docker context platform detection on WSL2

## Description
Fix Docker context platform detection to correctly return SSH endpoint for WSL2 in BOTH locations:
1. `_cai_expected_docker_host()` in `src/lib/docker.sh`
2. `_cai_update_docker_context()` in `src/lib/update.sh`

Currently, `cai update` hard-codes non-macOS expected host as `unix://$_CAI_CONTAINAI_DOCKER_SOCKET`, ignoring WSL2 which should use `ssh://containai-docker-daemon/var/run/containai-docker.sock`.

**Size:** M
**Files:** `src/lib/docker.sh`, `src/lib/update.sh`, possibly `src/lib/setup.sh` (for `_cai_is_wsl2()`)

## Approach

1. **Investigate `_cai_is_wsl2()` detection** (setup.sh):
   - Verify pattern matching for WSL2 kernel string
   - Check if detection works correctly on user's system

2. **Fix `_cai_update_docker_context()` in update.sh**:
   - Currently hard-codes: `expected_host="unix://$_CAI_CONTAINAI_DOCKER_SOCKET"`
   - Should call `_cai_expected_docker_host()` OR add explicit WSL2 handling:
     ```bash
     if _cai_is_wsl2; then
         expected_host="ssh://$_CAI_CONTAINAI_DOCKER_SSH_HOST$_CAI_CONTAINAI_DOCKER_SOCKET"
     else
         expected_host="unix://$_CAI_CONTAINAI_DOCKER_SOCKET"
     fi
     ```

3. **Verify `_cai_expected_docker_host()` order** (docker.sh):
   - Current order: macOS → container → WSL2 → default
   - Clarify intended behavior for "WSL2 host running inside sysbox container":
     - If SSH is desired: Check WSL2 before container
     - If unix:// is desired for nested: Current order is correct, but container detection may be triggering incorrectly

4. **Unify logic**: Consider having `_cai_update_docker_context()` call `_cai_expected_docker_host()` instead of duplicating platform logic

## Key context

Platform detection order in `_cai_expected_docker_host()`:
```bash
if _cai_is_macos; then ...
if _cai_is_container; then printf 'unix:///var/run/docker.sock'; return
if _cai_is_wsl2; then printf 'ssh://...'; return
printf 'unix://...'; return  # default Linux
```

`_cai_update_docker_context()` in update.sh has its own logic that doesn't check WSL2 at all.
## Approach

Investigate and fix the platform detection order in `_cai_expected_docker_host()` (lines 355-370):

1. **Check detection order**: Currently checks `_cai_is_container()` before `_cai_is_wsl2()`. If `cai update` runs with `/.dockerenv` somehow present, container detection wins over WSL2.

2. **Check `_cai_is_wsl2()` pattern** (setup.sh:99-121): Ensure it correctly detects WSL2 kernel string. Current pattern: `*[Mm]icrosoft-[Ss]tandard*` or `*microsoft-WSL2*`

3. **Add debug logging**: Temporarily add logging to see which branch is taken during detection

## Key context

Platform detection order in `_cai_expected_docker_host()`:
1. `_cai_is_macos` → Lima socket
2. `_cai_is_container` → inner Docker socket (`unix:///var/run/docker.sock`)
3. `_cai_is_wsl2` → SSH endpoint
4. Default → Linux socket

The SSH endpoint constant is: `$_CAI_CONTAINAI_DOCKER_SSH_HOST` = "containai-docker-daemon"
## Acceptance
- [ ] `_cai_expected_docker_host()` returns `ssh://containai-docker-daemon/var/run/containai-docker.sock` on WSL2 host
- [ ] `_cai_update_docker_context()` returns correct expected host for WSL2
- [ ] `cai doctor` shows matching expected/actual endpoints on WSL2 (no "wrong endpoint" warning)
- [ ] `cai update` does NOT "repair" a correctly configured SSH context on WSL2
- [ ] Context auto-repair does NOT trigger when SSH endpoint is already correct
- [ ] Nested container mode (running inside sysbox) still returns `unix:///var/run/docker.sock` for inner Docker
## Done summary
Fixed Docker context platform detection for WSL2 by replacing duplicated platform logic in `_cai_update_docker_context()` with a call to `_cai_expected_docker_host()`, which already correctly handles all platforms including WSL2's SSH endpoint.
## Evidence
- Commits: 41046eac379bdb4f7396708234f55870d60e0ba5
- Tests: shellcheck -x src/lib/update.sh, shellcheck -x src/lib/docker.sh, source src/containai.sh && _cai_is_wsl2, source src/containai.sh && _cai_expected_docker_host, source src/containai.sh && _cai_update --dry-run
- PRs:
