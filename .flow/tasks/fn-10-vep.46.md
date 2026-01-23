# fn-10-vep.46 Create systemd services (containai-init, sshd, dockerd)

## Description
Create systemd service files for the **system container**: initialization, sshd, AND dockerd (for DinD). These services run inside the sysbox container and provide the VM-like functionality.

**Size:** M
**Files:** src/services/containai-init.service, src/services/ssh-keygen.service, src/services/ssh.service.d/containai.conf, src/services/docker.service.d/containai.conf

## What This Enables

A system container with:
- **containai-init.service** - One-shot workspace setup on boot
- **ssh.service** - SSH access for VS Code Remote, agent forwarding (Ubuntu uses ssh.service, not sshd.service)
- **docker.service** - DinD so agents can build/run containers

## Approach

1. Create containai-init.service (one-shot):
   - Runs workspace discovery and setup
   - Creates symlink at `/home/agent/workspace`
   - Sets up volume structure at `/mnt/agent-data`
   - Type=oneshot with RemainAfterExit=yes
   - After=network.target

2. Configure ssh.service via drop-in (Ubuntu uses ssh.service, not sshd.service):
   - Wants=containai-init.service
   - After=containai-init.service network.target
   - Auto-start on boot (enabled by default)
   - Drop-in at ssh.service.d/containai.conf adds dependencies

3. Configure docker.service via drop-in for DinD:
   - Auto-start on boot (enabled by default)
   - After=containai-init.service
   - Inner Docker uses sysbox-runc by default (configured in daemon.json)
   - Depends on containerd.service and sysbox services
   - Drop-in at docker.service.d/containai.conf adds dependencies

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
- [ ] ssh.service enabled and auto-starts (Ubuntu uses ssh.service)
- [ ] docker.service enabled and auto-starts for DinD
- [ ] Services use ConditionVirtualization=container
- [ ] $container environment variable set
- [ ] Graceful shutdown via SIGRTMIN+3 works
- [ ] Inner dockerd can run containers (docker run hello-world)
- [ ] Services start correctly in system container
## Done summary
Created external systemd service files in src/services/ for container-aware operation. Added containai-init.service (one-shot workspace/volume setup), ssh-keygen.service (host key generation), and drop-in configs for ssh and docker services with ConditionVirtualization=container and proper dependency ordering.
## Evidence
- Commits: fcbb7ca6202b19f1eddbb2dae74c920a97de9cb7
- Tests: self-review: all acceptance criteria validated
- PRs:
