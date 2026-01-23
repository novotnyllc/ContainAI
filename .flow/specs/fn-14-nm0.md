# Fix cai setup Docker Isolation

## Overview

`cai setup` currently modifies the system's default Docker configuration (`/etc/docker/daemon.json`) and uses system Docker paths. This violates the principle that ContainAI should be completely isolated from the user's existing Docker installation.

**The Problem:**
- Native Linux setup modifies `/etc/docker/daemon.json` (system Docker)
- WSL2 setup also modifies system daemon.json for Sysbox runtime
- Path constants are inconsistent across `setup.sh`, `docker.sh`, and `install-containai-docker.sh`
- Socket naming inconsistent: `docker-containai.sock` vs `containai-docker.sock`
- No `cai --version` flag (only `cai version` subcommand)
- Separate `scripts/install-containai-docker.sh` duplicates setup logic

**The Solution:**
- Run a completely separate `dockerd` instance for ContainAI
- Use dedicated paths that never conflict with system Docker
- Never touch `/etc/docker/` at all
- Unify all path constants under a single naming convention
- Merge `install-containai-docker.sh` into `cai setup`
- Add `--version` flag to CLI

## Scope

**In scope:**
- Unify path constants to `containai-docker` naming convention
- Create dedicated systemd service `containai-docker.service`
- Use `/etc/containai/docker/daemon.json` (never touch `/etc/docker/`)
- Use `/var/lib/containai-docker/` for data root
- Use `/var/run/containai-docker.sock` for socket
- **Merge `scripts/install-containai-docker.sh` into `cai setup`** (supersedes fn-12-css.11)
- **Clean up old ContainAI paths on upgrade** (support re-running setup)
- Add `cai --version` flag
- Update `cai doctor` to check isolated Docker

**Out of scope:**
- macOS Lima VM changes (already isolated)
- Any modification to `/etc/docker/` (system Docker untouched)

## Approach

### Canonical Paths (standardize everywhere)

| Component | Path/Value |
|-----------|------------|
| Socket | `/var/run/containai-docker.sock` |
| Config | `/etc/containai/docker/daemon.json` |
| Data root | `/var/lib/containai-docker` |
| Exec root | `/var/run/containai-docker` |
| PID file | `/var/run/containai-docker.pid` |
| Bridge | `cai0` |
| Context | `containai-docker` |
| Service unit | `/etc/systemd/system/containai-docker.service` |
| Service name | `containai-docker.service` |

### Legacy Paths to Clean Up

| Component | Old Path | Action |
|-----------|----------|--------|
| Socket | `/var/run/docker-containai.sock` | Remove |
| Context | `containai-secure` | Remove |
| Systemd drop-in | `/etc/systemd/system/docker.service.d/containai-socket.conf` | Remove |

### Architecture Change

```
Before: cai setup -> modifies /etc/docker/daemon.json -> uses system dockerd
        scripts/install-containai-docker.sh -> separate isolated Docker

After:  cai setup -> creates isolated config -> runs containai-docker.service
        (scripts/install-containai-docker.sh deleted)
        (system Docker completely untouched)
```

## Quick commands

```bash
# Test the isolated Docker setup
source src/containai.sh
cai setup --dry-run

# Upgrade from old installation
cai setup  # automatically cleans old paths

# Verify isolation
cai doctor

# Check version flag works
cai --version
```

## Acceptance

- [ ] `cai setup` **never touches `/etc/docker/` at all**
- [ ] `cai setup` never modifies `/var/lib/docker/` at all
- [ ] Isolated Docker uses `/var/lib/containai-docker/` for storage
- [ ] Isolated Docker uses `/var/run/containai-docker.sock` for socket
- [ ] Systemd unit installed at `/etc/systemd/system/containai-docker.service`
- [ ] `scripts/install-containai-docker.sh` deleted (logic merged into setup.sh)
- [ ] **Old socket `/var/run/docker-containai.sock` removed if exists**
- [ ] **Old context `containai-secure` removed if exists**
- [ ] **Old drop-in `containai-socket.conf` removed if exists**
- [ ] `cai --version` prints version information
- [ ] `cai doctor` validates the isolated Docker instance
- [ ] All path constants unified across codebase
- [ ] Integration tests pass
- [ ] **Running `cai setup` twice is idempotent**

## Risks

| Risk | Mitigation |
|------|------------|
| Sysbox requires system Docker modification | Configure sysbox-runc in isolated daemon.json only |
| IP conflicts between Docker bridges | Use separate subnet `172.30.0.0/16` for cai0 |

## References

- Current setup: `src/lib/setup.sh:1847-1998` (native Linux flow)
- Isolated install script: `scripts/install-containai-docker.sh` (to be merged & deleted)
- Docker constants: `src/lib/docker.sh:306-309`
- Best practices: Multiple Docker daemons require unique data-root, exec-root, pidfile, socket
