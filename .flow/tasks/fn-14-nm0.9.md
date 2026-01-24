# fn-14-nm0.9 Add cai update command for updating existing installations

## Description
Add a `cai update` command that ensures an existing installation is in the required state and updates dependencies to their latest versions.

**Size:** M
**Files:** `src/containai.sh`, `src/lib/update.sh` (new)

## Current State

No update mechanism exists. Users must manually:
- Re-run `cai setup` (which may not update everything)
- Manually update Lima VM on macOS
- Manually check if systemd unit is current

## Approach

1. Create new `src/lib/update.sh` module with `_cai_update()` function

2. **Linux/WSL2 update flow:**
   - Check systemd unit file matches expected template
   - If different, update unit and reload daemon
   - Restart containai-docker service
   - Verify Docker context points to correct socket
   - Clean up legacy paths
   - Verify final state

3. **macOS Lima update flow:**
   - Check if Lima VM exists and is running
   - Stop VM if running
   - Delete VM: `limactl delete containai-docker --force`
   - Recreate VM with latest template (reuse `_cai_lima_create_vm()`)
   - Start VM and verify
   - Recreate context if needed

4. **Options:**
   - `--dry-run` - Show what would be done without doing it
   - `--force` - Skip confirmation prompts
   - `--lima-recreate` - Force Lima VM recreation even if current (macOS only)

5. Wire up in `containai.sh` command dispatch

## Key Context

- Lima VMs are safe to nuke - they only contain our Docker + Sysbox
- On Lima recreation, any running containers are lost (warn user)
- Systemd unit comparison: diff against template, not just existence
- Should reuse existing helper functions from setup.sh where possible
## Acceptance
- [ ] `cai update` command exists and is documented in `cai --help`
- [ ] `cai update --help` shows usage and options
- [ ] `cai update --dry-run` shows what would be updated without changes
- [ ] Linux/WSL2: Updates systemd unit if template changed
- [ ] Linux/WSL2: Restarts service after unit update
- [ ] Linux/WSL2: Verifies Docker context and socket
- [ ] macOS: Deletes and recreates Lima VM with latest config
- [ ] macOS: Warns about container loss before VM recreation
- [ ] macOS: `--force` skips confirmation on VM recreation
- [ ] macOS: `--lima-recreate` forces VM recreation even if current
- [ ] All platforms: Cleans up legacy paths during update
- [ ] All platforms: Final verification matches `cai doctor` checks
- [ ] `shellcheck -x src/lib/update.sh` passes
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
