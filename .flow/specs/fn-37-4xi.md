# fn-37-4xi Base Image Contract Documentation

## Overview

Document what ContainAI expects from base images. This helps users who want to create custom images or understand the system architecture.

**Priority:** LAST - Do this after all other epics are stable.

## Scope

### In Scope
- Create `docs/base-image-contract.md`
- Document required filesystem layout
- Document required user configuration
- Document required services (systemd, sshd, dockerd, containai-init)
- Document entrypoint requirements (MUST NOT override)
- Document recommended SDKs and agents
- Verify existing layer validation behavior aligns with documentation
- Verify existing config option documentation is complete

### Out of Scope
- Automated validation tooling (just documentation)
- Custom image building scripts
- Modifying validation behavior (already implemented)

## Contract Target

This contract applies to **images usable as ContainAI runtime images** (i.e., what users specify as template bases or `--image-tag`). The primary target is `ghcr.io/novotnyllc/containai:latest`.

## Approach

### Base Image Contract Document

Create `docs/base-image-contract.md`:

```markdown
# ContainAI Base Image Contract

This document describes what ContainAI expects from base images.

## Contract Target

This contract applies to images usable as ContainAI runtime images:
- Images used in template Dockerfiles (`FROM ...`)
- Images passed via `--image-tag`

The reference implementation is `ghcr.io/novotnyllc/containai:latest`.

## Required

### Filesystem Layout
- `/home/agent` - Agent user home directory
- `/mnt/agent-data` - Mount point for data volume
- `/opt/containai` - ContainAI scripts and tools (included in agents layer)
- `/usr/local/lib/containai/init.sh` - Init script for workspace setup

### User
- `agent` user (UID 1000) with passwordless sudo
- Home directory at `/home/agent`
- Shell: bash

### Services (systemd units)
- `containai-init.service` - Workspace setup (oneshot, runs on boot)
  - Creates volume structure in `/mnt/agent-data`
  - Sets up workspace symlinks
  - Loads environment from `.env`
- OpenSSH server (typically `ssh.service` or `sshd.service`), listening on port 22
- Docker daemon (`docker.service`) for Docker-in-Docker support

### Entrypoint/CMD Requirements

ContainAI runs containers with **no command argument**:
```bash
docker run ... <image>  # No CMD passed
```

This means:
- **ENTRYPOINT** must start systemd as PID 1 (`/sbin/init` or equivalent)
- **CMD** should not be set (or must not interfere with systemd boot)
- Templates/custom images MUST NOT override ENTRYPOINT or CMD

If ENTRYPOINT/CMD is overridden, systemd won't be PID 1, and all services (SSH, Docker, containai-init) will fail to start.

### Environment
- `container=docker` environment variable (for systemd container detection)
- `STOPSIGNAL SIGRTMIN+3` (proper systemd shutdown)
- PATH includes `/home/agent/.local/bin`

## Recommended

### AI Agents
- Claude Code CLI at `/home/agent/.local/bin/claude`
- Other agents as available

### SDKs (for full development environment)
- Node.js with nvm
- Python with uv/pipx
- Go, Rust, .NET as needed

## Validation Behavior

ContainAI validates template Dockerfiles by parsing the first `FROM` line:
1. Resolves ARG variables used in FROM (e.g., `ARG BASE=... / FROM $BASE`)
2. Checks if the base image matches one of these patterns:
   - `ghcr.io/novotnyllc/containai*`
   - `containai:*`
   - `containai-template-*:local` (locally built templates)
3. If not matched: WARN (not error) - ContainAI features may not work
4. If ARG variables cannot be resolved: WARN about unresolved variable

**Note**: This validates the *Dockerfile source*, not runtime layer history.

### Warning Suppression

To suppress the warning for intentional non-ContainAI bases:

```toml
# ~/.config/containai/config.toml
[template]
suppress_base_warning = true
```

See [Configuration Reference](configuration.md#template-section) for details.

Warning is suppressed in:
- Template builds (`cai run`, `cai build`)
- Doctor checks (`cai doctor`)
```

## Tasks

### fn-37-4xi.1: Create base-image-contract.md
Write comprehensive documentation covering all requirements, with concrete sections and accurate technical details.

### fn-37-4xi.2: Verify layer validation docs match implementation
Review and ensure existing validation documentation in `docs/configuration.md` and the new contract doc accurately describe current behavior (FROM-based validation, not layer history).

### fn-37-4xi.3: Verify suppression config docs are complete
Ensure `docs/configuration.md` covers `[template].suppress_base_warning` and link from the contract doc.

## Quick Commands

**Note**: Because the image ENTRYPOINT is `/sbin/init`, you cannot pass commands directly to `docker run`. Use `cai exec` against a running container instead.

```bash
# From a workspace directory, start a container
cd /path/to/workspace
cai shell  # or: cai shell --container test-contract

# Then inspect via exec (from the same workspace, or use --container)
cai exec -- ls -la /home/agent /mnt/agent-data /opt/containai
cai exec -- id agent
cai exec -- systemctl list-unit-files | grep -E 'ssh|docker|containai'

# Or target a specific container
cai exec --container test-contract -- id agent

# Or use docker exec directly (with ContainAI's docker context)
docker --context containai-docker exec <container-name> id agent

# Cleanup
cai stop

# Inspect FROM validation behavior (no running container needed)
grep -A5 '_cai_validate_template_base' src/lib/template.sh
```

## Acceptance

- [ ] `docs/base-image-contract.md` created with all required sections
- [ ] Document covers: filesystem, user, services (including containai-init), entrypoint/CMD behavior
- [ ] Validation behavior documented accurately (FROM-based, not layer history)
- [ ] All three accepted patterns documented: `ghcr.io/novotnyllc/containai*`, `containai:*`, `containai-template-*:local`
- [ ] Warning suppression config documented and linked
- [ ] Quick commands use `cai exec` or `docker exec` (not `docker run` with commands)

## Dependencies

- **fn-35-e0x**: Agent Extensibility (establishes agent installation patterns)
- All other epics should be complete

## References

- Template validation: `src/lib/template.sh:523` (`_cai_validate_template_base`)
- Config parsing: `src/lib/config.sh:535`
- Doctor checks: `src/lib/doctor.sh:3475`
- Configuration docs: `docs/configuration.md:302`
