# fn-10-vep.46 Create systemd services (containai-init, sshd, dockerd)

## Description
Create systemd service files for the **system container**: initialization, sshd, AND dockerd (for DinD). These services run inside the sysbox container and provide the VM-like functionality.

**Size:** M
**Files:** src/services/containai-init.service, src/services/sshd.service, src/services/docker.service

## What This Enables

A system container with:
- **containai-init.service** - One-shot workspace setup on boot
- **sshd.service** - SSH access for VS Code Remote, agent forwarding
- **docker.service** - DinD so agents can build/run containers

## Approach

1. Create containai-init.service (one-shot):
   - Runs workspace discovery and setup
   - Creates symlink at `/home/agent/workspace`
   - Sets up volume structure at `/mnt/agent-data`
   - Type=oneshot with RemainAfterExit=yes
   - After=network.target

2. Configure sshd.service:
   - Wants=containai-init.service
   - After=containai-init.service network.target
   - Auto-start on boot (enabled by default)
   - Standard sshd configuration

3. Configure docker.service for DinD:
   - Auto-start on boot (enabled by default)
   - After=containai-init.service
   - Inner Docker uses sysbox-runc by default (configured in daemon.json)
   - Depends on containerd.service

4. Use ConditionVirtualization=container for container-aware startup
5. Set $container environment variable for systemd

## Key context

- This is a SYSTEM CONTAINER - systemd manages real services
- Inner Docker uses sysbox-runc for security (configured in fn-10-vep.43)
- systemd requires $container env var for ConditionVirtualization
- Use SIGRTMIN+3 for graceful shutdown
- Services go in /etc/systemd/system/
- Do NOT configure --host flag in both daemon.json AND service file
- Pitfall: "Systemd drop-in ExecStart= clears then replaces" - use drop-ins for modifications
- Both sshd and dockerd always auto-start (user feedback)

## Acceptance
- [ ] containai-init.service created (one-shot, workspace setup)
- [ ] sshd.service enabled and auto-starts
- [ ] docker.service enabled and auto-starts for DinD
- [ ] Services use ConditionVirtualization=container
- [ ] $container environment variable set
- [ ] Graceful shutdown via SIGRTMIN+3 works
- [ ] Inner dockerd can run containers (docker run hello-world)
- [ ] Services start correctly in system container
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
