# fn-27-hbi.1 Safe update flow with container stop and systemd hooks

## Description
Add safe container management to the update flow and systemd hooks to ensure containers are cleanly stopped before sysbox/docker restarts.

**Size:** M
**Files:** `src/lib/update.sh`, `src/lib/docker.sh`, `src/lib/container.sh`

## Approach

1. **Container detection in update flow** - Modify `_cai_update()` to check for running ContainAI containers before sysbox/docker updates
   - Pattern: Use `_cai_container_list()` from `src/lib/container.sh`
   - Add `--stop-containers`, `--force`, `--dry-run` flags

2. **Systemd stop hooks** - Add drop-in unit or modify `_cai_dockerd_unit_content()` at `src/lib/docker.sh:442-493`:
   - Add `PartOf=sysbox-mgr.service sysbox-fs.service` for restart propagation
   - Add `Before=sysbox-mgr.service sysbox-fs.service` for stop ordering
   - Add `ExecStopPre=` to gracefully stop ContainAI containers

3. **Container stop helper** - Add `_cai_stop_containai_containers()` function:
   - Stop only containers in containai context (not other Docker containers)
   - Graceful stop with configurable timeout
   - Return list of stopped containers for potential restart

## Key context

- Current systemd unit at `src/lib/docker.sh:442-493` has `Wants=sysbox-mgr.service` but no stop hooks
- Use `BindsTo=` for tight coupling (stops on crash) vs `PartOf=` for restart-only propagation
- Set `TimeoutStopSec=180` to allow containers time to stop gracefully
## Acceptance
- [ ] `cai update` warns if containers running and sysbox/docker updates needed
- [ ] `cai update --dry-run` shows what would be stopped without stopping
- [ ] `cai update --stop-containers` stops containers, updates, then reports
- [ ] `cai update --force` proceeds without stopping (with warning)
- [ ] `systemctl stop sysbox-mgr` gracefully stops ContainAI containers first
- [ ] `systemctl restart containai-docker` gracefully handles container lifecycle
- [ ] Containers only stopped when updates are actually required
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
