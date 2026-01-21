# fn-10-vep.46 Create systemd services (containai-init, sshd, dockerd)

## Description
Create systemd service files for container initialization, sshd, and dockerd.

**Size:** M
**Files:** src/systemd/containai-init.service (new), sshd config, dockerd config

## Approach

1. Create `containai-init.service` (oneshot):
   - Runs workspace discovery logic (from entrypoint.sh)
   - Creates symlink at `/home/agent/workspace`
   - Sets up volume structure at `/mnt/agent-data`
   - Type=oneshot, RemainAfterExit=yes

2. Configure sshd.service:
   - Wants=containai-init.service
   - After=containai-init.service network.target
   - **Auto-starts** (enabled by default)

3. Configure dockerd.service:
   - **Auto-starts** (enabled by default, NOT optional)
   - After=containai-init.service
   - Provides DinD capability out of the box

## Key context

- Pitfall from memory: "Systemd drop-in ExecStart= clears then replaces"
- Use drop-ins for modifications, not full replacement
- oneshot + RemainAfterExit=yes ensures dependencies work
- Both sshd and dockerd always auto-start (user feedback)
## Approach

1. Create `containai-init.service` (oneshot):
   - Runs workspace discovery logic (from entrypoint.sh)
   - Creates symlink at `/home/agent/workspace`
   - Sets up volume structure at `/mnt/agent-data`
   - Type=oneshot, RemainAfterExit=yes

2. Configure sshd.service:
   - Wants=containai-init.service
   - After=containai-init.service network.target

3. Configure dockerd.service (optional, for DinD):
   - ConditionPathExists=/var/run/sysbox-fs (only in sysbox)
   - After=containai-init.service

## Key context

- Pitfall from memory: "Systemd drop-in ExecStart= clears then replaces"
- Use drop-ins for modifications, not full replacement
- oneshot + RemainAfterExit=yes ensures dependencies work
## Acceptance
- [ ] `containai-init.service` created as oneshot
- [ ] Service handles workspace discovery from `CAI_HOST_WORKSPACE` env
- [ ] Service creates symlink at `/home/agent/workspace`
- [ ] sshd enabled and auto-starts
- [ ] dockerd enabled and auto-starts (always, not optional)
- [ ] Services enabled by default in image
- [ ] `systemctl status containai-init` shows success after container start
- [ ] `docker info` works inside container immediately
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
