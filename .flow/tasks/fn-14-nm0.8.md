# fn-14-nm0.8 Rename macOS Lima VM and context to containai-docker

## Description
Rename macOS Lima VM and Docker context from `containai-secure` to `containai-docker` to match the naming convention used on Linux and WSL2.

**Size:** M
**Files:** `src/lib/setup.sh`, `src/lib/docker.sh`

## Current State

macOS Lima uses different names than Linux/WSL2:
- VM name: `containai-secure` (`setup.sh:77`)
- Socket path: `~/.lima/containai-secure/sock/docker.sock` (`setup.sh:80`)
- Context name: `containai-secure` (created in `_cai_lima_create_context()`)

Linux/WSL2 uses:
- Context name: `containai-docker` (from `docker.sh:308`)

## Approach

1. Update Lima constants in `setup.sh`:
   - `_CAI_LIMA_VM_NAME="containai-docker"` (was `containai-secure`)
   - `_CAI_LIMA_SOCKET_PATH="$HOME/.lima/containai-docker/sock/docker.sock"`

2. Update `_cai_lima_create_context()` to create `containai-docker` context (or better, use `$_CAI_CONTAINAI_DOCKER_CONTEXT`)

3. Add migration logic in `_cai_setup_macos()`:
   - Detect old `containai-secure` VM
   - Offer to delete and recreate as `containai-docker`
   - Or just create new one alongside (less disruptive)

4. Update `_cai_cleanup_legacy_paths()` to handle Lima legacy paths

## Key Context

- Lima VMs are stored in `~/.lima/<vm-name>/`
- Socket is at `~/.lima/<vm-name>/sock/docker.sock`
- Lima commands: `limactl list`, `limactl delete <vm>`, `limactl start <vm>`
- The VM contains our isolated Docker + Sysbox installation
- Safe to nuke and recreate since it's dedicated to ContainAI
## Acceptance
- [ ] `_CAI_LIMA_VM_NAME` changed to `containai-docker`
- [ ] `_CAI_LIMA_SOCKET_PATH` updated to use new VM name
- [ ] `_cai_lima_create_context()` creates `containai-docker` context
- [ ] Uses `$_CAI_CONTAINAI_DOCKER_CONTEXT` constant (not hardcoded)
- [ ] Setup detects old `containai-secure` VM and offers migration
- [ ] Clean setup on fresh macOS creates `containai-docker` VM and context
- [ ] `cai setup --dry-run` on macOS shows new naming
- [ ] `cai doctor` on macOS finds the `containai-docker` context
- [ ] `shellcheck -x src/lib/setup.sh` passes
## Done summary
## Summary

Renamed macOS Lima VM and Docker context from `containai-secure` to `containai-docker` to unify naming across all platforms (Linux, WSL2, macOS).

### Changes Made

1. **Updated Lima constants in setup.sh**:
   - `_CAI_LIMA_VM_NAME` now uses `$_CAI_CONTAINAI_DOCKER_CONTEXT` (evaluates to `containai-docker`)
   - `_CAI_LIMA_SOCKET_PATH` updated to use new VM name: `~/.lima/containai-docker/sock/docker.sock`
   - Added `_CAI_LEGACY_LIMA_VM_NAME="containai-secure"` for migration

2. **Added Lima migration to `_cai_cleanup_legacy_paths()`**:
   - Detects old `containai-secure` Lima VM
   - Stops and deletes the legacy VM during cleanup
   - Works silently if Lima is not installed

3. **Updated `_cai_lima_create_context()`**:
   - Uses `$_CAI_CONTAINAI_DOCKER_CONTEXT` constant instead of hardcoded name
   - Creates `containai-docker` context on macOS

4. **Updated `_cai_lima_verify_install()`**:
   - Uses context name variable for all checks
   - Properly warns if `containai-docker` (not `containai-secure`) is active

5. **Updated `_cai_setup_macos()` output messages**:
   - All user-facing messages now reference `containai-docker`

6. **Updated doctor validation (`_cai_validate_secure_engine_common`)**:
   - macOS now expects `containai-docker` context like Linux/WSL2

7. **Updated help text**:
   - All Lima VM management examples use `containai-docker`

8. **Updated legacy functions for consistency**:
   - `_cai_create_containai_context()`, `_cai_verify_sysbox_install()`, and `_cai_verify_sysbox_install_linux()` now use the constant

### Result

All platforms now consistently use `containai-docker` as the Docker context name:
- Linux: Uses isolated daemon at `/var/run/containai-docker.sock`
- WSL2: Uses isolated daemon at `/var/run/containai-docker.sock`
- macOS: Uses Lima VM at `~/.lima/containai-docker/sock/docker.sock`

Old macOS installs with `containai-secure` VM will be migrated on next `cai setup`.
## Evidence
- Commits: 0592fdb, 13ce372
- Tests: shellcheck -x src/lib/setup.sh (passes), source src/containai.sh && echo $_CAI_LIMA_VM_NAME (containai-docker)
- PRs:
