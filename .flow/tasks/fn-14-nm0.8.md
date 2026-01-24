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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
