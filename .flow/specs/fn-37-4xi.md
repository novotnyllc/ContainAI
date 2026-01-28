# fn-37-4xi Base Image Contract Documentation

## Overview

Document what ContainAI expects from base images. This helps users who want to create custom images or understand the system architecture.

**Priority:** LAST - Do this after all other epics are stable.

## Scope

### In Scope
- Create `docs/base-image-contract.md`
- Document required filesystem layout
- Document required user configuration
- Document required services (systemd, sshd, dockerd)
- Document entrypoint requirements (MUST NOT override)
- Document recommended SDKs and agents
- Document layer validation behavior

### Out of Scope
- Automated validation tooling (just documentation)
- Custom image building scripts

## Approach

### Base Image Contract Document

Create `docs/base-image-contract.md`:

```markdown
# ContainAI Base Image Contract

This document describes what ContainAI expects from base images.

## Required

### Filesystem Layout
- `/home/agent` - Agent user home directory
- `/mnt/agent-data` - Mount point for data volume
- `/opt/containai` - ContainAI scripts and tools

### User
- `agent` user (UID 1000) with passwordless sudo
- Home directory at `/home/agent`
- Shell: bash

### Services
- systemd as PID 1 (init system)
- sshd running on port 22
- dockerd (for Docker-in-Docker)

### Entrypoint
- MUST NOT override ENTRYPOINT (systemd needs to be PID 1)
- MUST NOT override CMD

### Environment
- PATH includes `/home/agent/.local/bin`
- Standard development tools available

## Recommended

### AI Agents
- Claude Code CLI at `/home/agent/.local/bin/claude`
- Other agents as available

### SDKs
- Node.js with nvm
- Python with uv/pipx
- Go, Rust, .NET as needed

## Validation

ContainAI validates base images by checking:
1. Layer history includes `ghcr.io/novotnyllc/containai` or `containai:`
2. If not found: WARN (not error) with explanation

To suppress warning:
```toml
[template]
suppress_base_warning = true
```
```

## Tasks

### fn-37-4xi.1: Create base-image-contract.md
Write comprehensive documentation covering all requirements.

### fn-37-4xi.2: Add layer validation to template builds
Implement warning when template doesn't derive from ContainAI image.

### fn-37-4xi.3: Add config option for warning suppression
`[template].suppress_base_warning = true` in config.toml.

## Quick commands

```bash
# Check layer history
docker image history containai:latest

# Verify required paths
docker run --rm containai:latest ls -la /home/agent /mnt/agent-data /opt/containai

# Check user
docker run --rm containai:latest id agent
```

## Acceptance

- [ ] `docs/base-image-contract.md` created
- [ ] Document covers filesystem, user, services, entrypoint
- [ ] Layer validation warns for non-ContainAI bases
- [ ] Warning suppression config option works

## Dependencies

- **fn-35-e0x**: Agent Extensibility (establishes agent installation patterns)
- All other epics should be complete

## References

- Docker image layers: https://docs.docker.com/storage/storagedriver/
- systemd in containers: https://developers.redhat.com/blog/2019/04/24/how-to-run-systemd-in-a-container
