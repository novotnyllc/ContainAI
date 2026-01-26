# fn-27-hbi.1 Safe update flow with container stop and systemd hooks

## Description
Add safe container management to the update flow and systemd hooks to ensure containers are cleanly stopped before sysbox/docker restarts or systemd unit template updates.

**Size:** M
**Files:** `src/lib/update.sh`, `src/lib/docker.sh`, `src/lib/container.sh`

## Approach

1. **Container detection in update flow** - Modify `_cai_update_linux_wsl2()` to check for running ContainAI containers before sysbox/docker updates or unit template changes
   - Use existing `_containai_list_containers_for_context()` from `src/lib/container.sh:2319`
   - Add `--stop-containers` and `--dry-run` flags
   - Keep existing `--force` semantics (skip confirmation prompts)
   - Detect updates needed: sysbox version mismatch, dockerd bundle update, OR unit template change

2. **Default behavior when updates needed + containers running**:
   - Abort with actionable message (do NOT proceed silently or update unsafely)
   - List running containers that would be affected
   - Suggest: "Run with --stop-containers to safely stop containers before update"
   - Exit with non-zero status

3. **Systemd stop hooks** - Add ExecStopPre to `_cai_dockerd_unit_content()` at `src/lib/docker.sh:442-493`:
   - Add `ExecStopPre=/bin/sh -c 'DOCKER_HOST=unix:///var/run/containai-docker.sock docker ps -q --filter label=containai.managed=true | xargs -r docker stop -t 60 || true'`
   - This stops only labeled containers in the containai-docker engine
   - Note: Legacy ancestor-image-only containers (no label) are NOT stopped by systemd hook; they should be rare and can be handled manually
   - Set `TimeoutStopSec=180` to allow containers time to stop gracefully
   - Add `PartOf=sysbox-mgr.service sysbox-fs.service` for restart propagation

4. **Container stop helper** - Add `_cai_stop_containai_containers()` function in `src/lib/update.sh`:
   - Reuse `_containai_stop_all()` from `src/lib/container.sh:2352` for bulk stop
   - Graceful stop with configurable timeout (default 60s)
   - Return list of stopped containers for logging

## Key context

- Existing helpers: `_containai_list_containers_for_context()` at `src/lib/container.sh:2319`, `_containai_stop_all()` at `src/lib/container.sh:2352`
- Label filter: `containai.managed=true` defined at `src/lib/container.sh:59`
- Current systemd unit at `src/lib/docker.sh:442-493` has `Wants=sysbox-mgr.service` but no stop hooks
- Unit template changes trigger restart via `_cai_update_systemd_unit` - this counts as "update required"
- Use DOCKER_HOST in ExecStopPre to target only containai-docker engine, not default Docker

## Acceptance
- [ ] `cai update` aborts with actionable message if containers running and updates needed
- [ ] `cai update --dry-run` shows what would be stopped without stopping
- [ ] `cai update --stop-containers` stops containers, updates, then reports
- [ ] `systemctl stop containai-docker` gracefully stops labeled ContainAI containers first via ExecStopPre
- [ ] `systemctl restart containai-docker` gracefully handles container lifecycle
- [ ] Containers only stopped when updates are actually required (sysbox, dockerd, or unit change)
- [ ] Existing `--force` flag semantics preserved (skip prompts, not skip container stop)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
