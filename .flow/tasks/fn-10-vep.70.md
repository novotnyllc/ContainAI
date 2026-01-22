# fn-10-vep.70 Implement cai uninstall command for clean removal

## Description
Implement `cai uninstall` command that cleanly removes ContainAI's system-level installation components. User configuration and data are preserved by default.

**Size:** M
**Files:** src/lib/uninstall.sh, src/containai.sh (add uninstall subcommand)

## What Gets Removed

### Always removed (system-level installation):
1. **containai-docker.service** - Stop, disable, remove the systemd unit
2. **Docker context**: `containai-secure` / `docker-containai`

### Removed with --containers flag:
- All containers with `containai.*` labels
- Associated volumes (with `--volumes` flag)

### NOT removed (user config/data - preserved always):
- `~/.config/containai/` - SSH keys, config.toml (user may reinstall)
- `~/.ssh/containai.d/` - SSH host configs (harmless if containers gone)
- Include directive in `~/.ssh/config` (harmless, points to existing dir)
- `/etc/containai/docker/` - daemon.json (reinstall can reuse)
- `/var/lib/containai-docker/` - Docker data (images, layers)
- Sysbox packages - apt packages remain (user may want for other purposes)
- Lima VM (macOS) - contains user data

## Approach

1. **Flags**:
   - `--dry-run`: Show what would be removed without removing
   - `--containers`: Stop and remove containai containers
   - `--volumes`: Also remove container volumes (requires --containers)
   - `--force`: Skip confirmation prompts

2. **Uninstall order**:
   ```
   1. Stop/remove containers (if --containers)
   2. Remove volumes (if --volumes)
   3. Remove Docker context
   4. Stop containai-docker.service
   5. Disable containai-docker.service
   6. Remove /etc/systemd/system/containai-docker.service
   7. systemctl daemon-reload
   ```

3. **Safety checks**:
   - Confirm before removing (unless --force)
   - Detect running containers and warn
   - Show what will be preserved

4. **Best practices for systemd service removal**:
   - Stop service first: `systemctl stop containai-docker`
   - Disable to remove symlinks: `systemctl disable containai-docker`
   - Remove unit file: `rm /etc/systemd/system/containai-docker.service`
   - Reload daemon: `systemctl daemon-reload`
   - Do NOT remove /var/lib/containai-docker (user data)

## Key context

- ContainAI runs its own Docker daemon, separate from Docker Desktop or system Docker
- Socket at `/var/run/containai-docker.sock`
- Config at `/etc/containai/docker/daemon.json`
- Data at `/var/lib/containai-docker/`
- User config is sacred - never remove without explicit separate command
- Reinstalling after uninstall should "just work" with existing config/data

## Acceptance
- [ ] `cai uninstall` command implemented
- [ ] Stops and disables containai-docker.service
- [ ] Removes systemd unit file
- [ ] Runs systemctl daemon-reload
- [ ] Removes Docker context
- [ ] `--dry-run` shows what would be removed
- [ ] `--containers` stops/removes containai containers
- [ ] `--volumes` removes container volumes
- [ ] Does NOT remove ~/.config/containai/
- [ ] Does NOT remove /etc/containai/docker/
- [ ] Does NOT remove /var/lib/containai-docker/
- [ ] Confirmation prompt (skippable with --force)
- [ ] Clean exit with summary of what was removed

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
