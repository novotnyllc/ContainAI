# fn-49-devcontainer-integration.2 Create ContainAI devcontainer feature

## Description

Create the ContainAI devcontainer feature that provides sysbox verification, symlink creation, SSH service, and DinD support.

### Feature Structure

```
src/devcontainer/feature/
├── devcontainer-feature.json
├── install.sh
├── verify-sysbox.sh
├── init.sh
└── start.sh
```

### devcontainer-feature.json Options

- `dataVolume`: Name of cai data volume (default: auto-derived)
- `enableSsh`: Run sshd for non-VS Code access (default: true)
- `sshPort`: SSH port (default: 2322)
- `installDocker`: Install Docker for DinD (default: true)
- `remoteUser`: User for symlinks (default: auto-detect)

### Scripts

1. **install.sh** (build-time)
   - Store config to `/usr/local/share/containai/config`
   - Create verify-sysbox.sh, init.sh, start.sh
   - Install openssh-server if enableSsh
   - Install Docker if installDocker

2. **verify-sysbox.sh**
   - UID map check (0 not mapped to 0)
   - Nested userns test (unshare --user)
   - Sysboxfs mount check
   - CAP_SYS_ADMIN capability probe
   - Require 3+ checks to pass

3. **init.sh** (postCreateCommand)
   - Run sysbox verification
   - Create symlinks from ~ to /mnt/agent-data (mirrors sync-manifest.toml)
   - Symlinks: Claude, Git, GitHub CLI, shell, editors, etc.

4. **start.sh** (postStartCommand)
   - Start sshd if enabled
   - Re-verify sysbox

### Symlinks Created (based on sync-manifest.toml)

- `~/.claude.json` → `/mnt/agent-data/claude/claude.json`
- `~/.claude/credentials.json` → `/mnt/agent-data/claude/credentials.json`
- `~/.gitconfig` → `/mnt/agent-data/git/gitconfig`
- `~/.config/gh/hosts.yml` → `/mnt/agent-data/config/gh/hosts.yml`
- (and more per manifest)

## Acceptance

- [ ] Feature installs on any base image (Debian/Ubuntu preferred)
- [ ] Sysbox verification passes in sysbox, fails in regular docker
- [ ] Symlinks created correctly when data volume mounted
- [ ] SSH starts on configured port
- [ ] Docker available for DinD when enabled
- [ ] Hard-fail with clear error message when not in sysbox

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
