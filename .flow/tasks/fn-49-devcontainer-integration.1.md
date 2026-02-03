# fn-49-devcontainer-integration.1 Implement cai-docker wrapper

## Description

Create the smart docker wrapper (`cai-docker`) that detects ContainAI devcontainers and routes them to the sysbox runtime.

### Location
`src/devcontainer/cai-docker` (shell script)

### Core Functions

1. **Devcontainer detection via VS Code labels**: Parse `--label devcontainer.config_file=...` and `--label devcontainer.local_folder=...` from docker create/run args (NOT `--workspace-folder` which VS Code doesn't pass)
2. **ContainAI marker detection**: Check for `containai` feature in devcontainer.json using proper JSONC parsing (python3 state machine, not sed)
3. **Runtime enforcement**: Add `--runtime=sysbox-runc` to enforce sysbox at launch time
4. **Credential validation**: When `enableCredentials=false`, validate volume has `.containai-no-secrets` marker; warn and skip mount if missing
5. **Data volume injection**: Add `-v sandbox-agent-data:/mnt/agent-data:rw` (or configured volume) if validated
6. **SSH port injection**: Pass allocated port to container via `-e CONTAINAI_SSH_PORT=<port>`
7. **Label injection** (complete set):
   - `containai.managed=true` (required for cai ps/stop/gc)
   - `containai.type=devcontainer`
   - `containai.devcontainer.workspace=<name>`
   - `containai.data-volume=<volume>`
   - `containai.ssh-port=<port>`
   - `containai.created=<ISO8601-UTC>`
8. **SSH config management**: Update `~/.ssh/containai.d/devcontainer-<workspace>` with dynamically allocated port (reuse existing SSH config patterns, check existing reserved ports)
9. **Context routing**: Exec to `docker --context containai-docker`

### Key Design Decisions

**Detection mechanism**: VS Code Dev Containers passes labels like:
- `--label devcontainer.config_file=/path/to/.devcontainer/devcontainer.json`
- `--label devcontainer.local_folder=/path/to/workspace`

Parse these labels from the docker command args to locate the devcontainer.json.

**JSONC parsing**: Use python3 with a proper state-machine comment stripper that handles:
- `// line comments`
- `/* block comments */`
- Comment-like sequences inside JSON strings (e.g., `"url": "https://example.com"`)

Do NOT use sed-based comment stripping which fails on edge cases.

**SSH port allocation**: Use dynamic port allocation (range 2400-2499) with:
- **Shared lock file**: Use `~/.config/containai/.ssh-port.lock` (SAME as `cai` uses) to coordinate with concurrent `cai` commands
- **Lock held across allocation AND docker exec**: Acquire lock before allocation, hold it until `exec docker` replaces the process. This prevents races where `cai` could allocate the same port before the container is created and labeled.
  - Linux: `flock` on FD 200 (inherited by exec) - FULL COORDINATION
  - macOS: `flock` not available - V1 KNOWN LIMITATION (see below)
- **Shared port directory**: Use `~/.config/containai/ports/` to share reservations with `cai`
- **Cross-platform port check**: Use `ss` on Linux, `lsof` on macOS
- **Correct context**: Query `containai-docker` context for existing `containai.ssh-port` labels, not default context

**V1 Known Limitation (macOS)**: Without `flock`, concurrent `cai` and `cai-docker` operations may race on port allocation. Port reservation files provide best-effort coordination. Full fix requires V2 enhancement where `cai` reads shared port files.

**Portability**:
- Use `date -u +%Y-%m-%dT%H:%M:%SZ` (POSIX) instead of `date -Iseconds` (GNU only)
- Use `~/.ssh/containai.d/<workspace>` with Include directive (not direct sed edits to ~/.ssh/config)

### Installation Path
- `~/.local/bin/cai-docker` (installed by `cai setup`)

### V1 Limitations
- Docker CLI only (not docker-compose)
- No compose-aware injection

## Acceptance

- [ ] Detects ContainAI marker via VS Code labels (devcontainer.config_file, devcontainer.local_folder)
- [ ] Parses JSONC correctly using python3 state machine (not sed)
- [ ] Enforces `--runtime=sysbox-runc` at launch time
- [ ] Routes to `containai-docker` context (reuses existing platform-specific context)
- [ ] Passes through to regular docker when no ContainAI marker
- [ ] Validates volume for credentials when `enableCredentials=false` (checks `.containai-no-secrets` marker)
- [ ] Injects data volume mount only if validated (default: sandbox-agent-data)
- [ ] Passes SSH port to container via `-e CONTAINAI_SSH_PORT=<port>`
- [ ] Injects complete label set: `containai.managed`, `containai.type`, `containai.devcontainer.workspace`, `containai.data-volume`, `containai.ssh-port`, `containai.created`
- [ ] Uses portable timestamp format (`date -u +%Y-%m-%dT%H:%M:%SZ`)
- [ ] Dynamically allocates SSH port with:
  - Shared lock file (`~/.config/containai/.ssh-port.lock`, same as `cai`)
  - Lock held across allocation AND docker exec (prevents races)
  - Linux: flock on FD inherited by exec (full coordination)
  - macOS: best-effort via port files (V1 known limitation - no flock)
  - Shared port directory (`~/.config/containai/ports/`)
  - Cross-platform port check (`ss` on Linux, `lsof` on macOS)
  - Queries `containai-docker` context for existing `containai.ssh-port` labels
- [ ] Updates ~/.ssh/containai.d/ with Include directive pattern
- [ ] Works with VS Code Dev Containers extension

## Dependencies

- **Depends on**: fn-49-devcontainer-integration.10 (Add no-secrets marker to cai import)

## Done summary
## Implementation Summary

Implemented the `cai-docker` smart Docker wrapper for ContainAI devcontainers.

### Key Features
1. **Devcontainer detection via VS Code labels**: Parses `--label devcontainer.config_file=...` and `--label devcontainer.local_folder=...`
2. **ContainAI marker detection**: Proper JSONC parsing via python3 state machine, specifically checking `.features` object
3. **Runtime enforcement**: Adds `--runtime=sysbox-runc` at launch time
4. **Credential validation**: Validates volume has `.containai-no-secrets` marker when `enableCredentials=false`
5. **Data volume injection**: Uses `--mount type=volume` for explicit volume semantics; validates volume names (rejects paths)
6. **SSH port injection**: Passes allocated port via `-e CONTAINAI_SSH_PORT=<port>`
7. **Complete label set**: managed, type, workspace, data-volume, ssh-port, created
8. **SSH config management**: Updates `~/.ssh/containai.d/` with Include directive at top
9. **Context routing**: Routes to `containai-docker` context for ContainAI containers

### Security Fixes
- Volume name validation rejects paths and bind mount syntax
- Workspace name sanitization for SSH config safety
- As dockerPath wrapper, correctly handles argv without "docker" prefix

### Files
- `src/devcontainer/cai-docker` - Main wrapper (680 lines)
- `tests/unit/test-cai-docker.sh` - Unit tests (27 tests, all passing)
## Evidence
- Commits:
- Tests: {'type': 'unit', 'file': 'tests/unit/test-cai-docker.sh', 'count': 27, 'passed': 27}
- PRs:
