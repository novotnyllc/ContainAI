# fn-10-vep.40 Create docker-containai context with sysbox-runc default

## Description
Install a SEPARATE docker-ce instance alongside any existing Docker Desktop. This docker-ce uses sysbox-runc as default runtime for creating system containers - VM-like containers that can run systemd, services, and Docker itself.

**Size:** L
**Files:** lib/setup.sh, lib/docker.sh, scripts/install-containai-docker.sh

## Why System Containers?

System containers provide:
- **VM-like behavior** - systemd as PID 1, multiple services
- **Secure DinD** - Docker-in-Docker without --privileged
- **Automatic isolation** - Sysbox handles user namespace mapping automatically via /etc/subuid and /etc/subgid
- **No manual userns config** - Unlike raw Docker, no need to configure uid/gid mappings manually

## Approach

1. Install docker-ce (not Docker Desktop):
   - Use official Docker apt/yum repository
   - Install docker-ce, docker-ce-cli, containerd.io
   - Do NOT interfere with existing Docker Desktop

2. Install sysbox:
   - Install sysbox-ce from Nestybox releases
   - Start sysbox-mgr and sysbox-fs services
   - Sysbox configures /etc/subuid and /etc/subgid automatically

3. Configure isolated paths:
   - Socket: `/var/run/containai-docker.sock`
   - Config: `/etc/containai/docker/daemon.json`
   - Data: `/var/lib/containai-docker/`
   - Systemd unit: `containai-docker.service`

4. Configure daemon.json for sysbox as default:
   ```json
   {
     "runtimes": {
       "sysbox-runc": {
         "path": "/usr/bin/sysbox-runc"
       }
     },
     "default-runtime": "sysbox-runc",
     "hosts": ["unix:///var/run/containai-docker.sock"],
     "data-root": "/var/lib/containai-docker"
   }
   ```

5. Create Docker context:
   - `docker context create docker-containai --docker "host=unix:///var/run/containai-docker.sock"`

## Key context

- Docker Desktop uses /var/run/docker.sock - we use a separate socket
- Sysbox requires its own services (sysbox-mgr, sysbox-fs)
- Sysbox automatically handles user namespace mapping - no manual configuration needed
- dockerd must specify -H flag OR hosts in daemon.json, not both
- User may not have sudo - handle gracefully

## Acceptance
- [ ] docker-ce installed separately from Docker Desktop
- [ ] sysbox-ce installed and configured
- [ ] Containai docker uses `/var/run/containai-docker.sock`
- [ ] Config at `/etc/containai/docker/daemon.json`
- [ ] Data at `/var/lib/containai-docker/`
- [ ] sysbox-runc set as default runtime
- [ ] sysbox services running (sysbox-mgr, sysbox-fs)
- [ ] `docker-containai` context created pointing to containai socket
- [ ] `docker --context docker-containai info` shows sysbox-runc as default
- [ ] Docker Desktop (if present) continues to work unchanged
- [ ] `cai doctor` validates containai docker setup
## Done summary
Implemented docker-containai context with sysbox-runc as default runtime. Created install-containai-docker.sh script that installs a separate docker-ce instance with isolated paths (socket, config, data, exec-root, pidfile, bridge) to avoid conflicts with Docker Desktop. Added helper functions in lib/docker.sh and validation in lib/doctor.sh.
## Evidence
- Commits: 29b5e65, 096bb68, c5bacc8, 300ed9c, ca00040, 39bc8ad
- Tests: bash -n scripts/install-containai-docker.sh, bash -n src/lib/docker.sh, bash -n src/lib/doctor.sh, bash -n src/lib/setup.sh
- PRs: