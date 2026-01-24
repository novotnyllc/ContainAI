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
- macOS Lima uses `containai-secure` context while Linux/WSL2 uses `containai-docker`
- `cai uninstall` doesn't remove the `containai-docker` context we actually create
- No way to update an existing installation to latest state

**The Solution:**
- Run a completely separate `dockerd` instance for ContainAI
- Use dedicated paths that never conflict with system Docker
- Never touch `/etc/docker/` at all
- Unify all path constants under a single naming convention
- Merge `install-containai-docker.sh` into `cai setup`
- Add `--version` flag to CLI
- **Use `containai-docker` context name on ALL platforms (Linux, WSL2, macOS)**
- **Update `cai uninstall` to properly clean up the isolated Docker instance**
- **Add `cai update` command to ensure state and update dependencies**

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
- **macOS Lima: change context from `containai-secure` to `containai-docker`**
- **macOS Lima: rename VM from `containai-secure` to `containai-docker`**
- **Update `cai uninstall` to remove `containai-docker` context**
- **Add `cai update` command for updating existing installations**

**Out of scope:**
- Any modification to `/etc/docker/` (system Docker untouched)

## Approach

### Canonical Paths (standardize everywhere)

| Component | Path/Value |
|-----------|------------|
| Socket | `/var/run/containai-docker.sock` (Linux/WSL2) |
| Socket | `~/.lima/containai-docker/sock/docker.sock` (macOS) |
| Config | `/etc/containai/docker/daemon.json` |
| Data root | `/var/lib/containai-docker` |
| Exec root | `/var/run/containai-docker` |
| PID file | `/var/run/containai-docker.pid` |
| Bridge | `cai0` |
| **Context** | **`containai-docker`** (ALL platforms) |
| Service unit | `/etc/systemd/system/containai-docker.service` |
| Service name | `containai-docker.service` |
| Lima VM | `containai-docker` (was `containai-secure`) |

### Legacy Paths to Clean Up

| Component | Old Path | Action |
|-----------|----------|--------|
| Socket | `/var/run/docker-containai.sock` | Remove |
| Context | `containai-secure` | Remove |
| Context | `docker-containai` | Remove |
| Systemd drop-in | `/etc/systemd/system/docker.service.d/containai-socket.conf` | Remove |
| Lima VM | `containai-secure` | Migrate or remove |

### Architecture Change

```
Before: cai setup -> modifies /etc/docker/daemon.json -> uses system dockerd
        scripts/install-containai-docker.sh -> separate isolated Docker
        macOS uses containai-secure context, Linux uses containai-docker

After:  cai setup -> creates isolated config -> runs containai-docker.service
        cai update -> ensures state, updates dependencies (Lima VM, etc.)
        cai uninstall -> properly removes containai-docker context
        (scripts/install-containai-docker.sh deleted)
        (system Docker completely untouched)
        ALL platforms use containai-docker context
```

### cai update Command

Purpose: Ensure existing installation is in required state and dependencies are up to date.

**What it does:**
- Linux/WSL2: Update systemd unit if changed, restart service, verify state
- macOS Lima: Nuke and recreate VM with latest config (safe - it's our dedicated VM)
- All platforms: Update Docker context if socket path changed
- All platforms: Clean up any legacy paths/contexts
- All platforms: Verify final state matches expected

**Options:**
- `--dry-run` - Show what would be done
- `--force` - Skip confirmation prompts
- `--lima-recreate` - Force Lima VM recreation (macOS only)

## Quick commands

```bash
# Test the isolated Docker setup
source src/containai.sh
cai setup --dry-run

# Upgrade from old installation
cai setup  # automatically cleans old paths

# Update existing installation
cai update --dry-run
cai update

# Verify isolation
cai doctor

# Check version flag works
cai --version

# Test uninstall (dry-run)
cai uninstall --dry-run
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
- [ ] **macOS Lima uses `containai-docker` context (not `containai-secure`)**
- [ ] **macOS Lima VM named `containai-docker` (not `containai-secure`)**
- [ ] **`cai uninstall` removes `containai-docker` context**
- [ ] **`cai uninstall --dry-run` shows `containai-docker` context removal**
- [ ] **`cai update` command exists and works**
- [ ] **`cai update` on macOS can recreate Lima VM**
- [ ] **`cai update --dry-run` shows what would be updated**

## Risks

| Risk | Mitigation |
|------|------------|
| Sysbox requires system Docker modification | Configure sysbox-runc in isolated daemon.json only |
| IP conflicts between Docker bridges | Use separate subnet `172.30.0.0/16` for cai0 |
| Existing macOS users have `containai-secure` VM | Migration path: detect old VM, offer to migrate or remove |
| Lima VM recreation loses running containers | Warn user, require confirmation unless --force |

## References

- Current setup: `src/lib/setup.sh:1847-1998` (native Linux flow)
- Isolated install script: `scripts/install-containai-docker.sh` (to be merged & deleted)
- Docker constants: `src/lib/docker.sh:306-309`
- Uninstall: `src/lib/uninstall.sh:64` (contexts array needs `containai-docker`)
- Lima context creation: `src/lib/setup.sh:1952-2002`
- Lima VM name: `src/lib/setup.sh:77` (`_CAI_LIMA_VM_NAME`)
- Best practices: Multiple Docker daemons require unique data-root, exec-root, pidfile, socket
