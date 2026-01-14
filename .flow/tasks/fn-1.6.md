# fn-1.6 Add GitHub Copilot and VS Code data volume mounts

## Description
Add volume mount for GitHub Copilot CLI authentication to persist across container rebuilds.

### Volume Mount to Add

| Volume | Container Path | Purpose |
|--------|----------------|---------|
| `docker-github-copilot` | `/home/agent/.config/github-copilot` | Copilot CLI auth (`hosts.json`) |

**Note**: The `docker-vscode-data` volume was DROPPED. VS Code Remote Containers stores all data (globalStorage, workspaceStorage, extensions, settings) under `~/.vscode-server`, which is covered by `docker-vscode-server`. The `~/.config/Code` path is for local VS Code, not Remote Containers.

### GitHub Copilot Auth Locations

Per research, Copilot stores auth in two places:
- **CLI**: `~/.config/github-copilot/hosts.json` (OAuth tokens) - requires separate volume for credential isolation
- **VS Code Extension**: `~/.vscode-server/data/User/globalStorage/github.copilot/` - covered by vscode-server volume

### Implementation

1. Update Dockerfile to create mount point directory:
   ```dockerfile
   RUN mkdir -p /home/agent/.config/github-copilot \
       && chown -R agent:agent /home/agent/.config
   ```

2. Ensure proper permissions (agent user owns directory)

### Reference

- Existing volume pattern: `claude/sync-plugins.sh:21-23`
- GitHub Copilot CLI auth: `~/.config/github-copilot/hosts.json`
- VS Code Copilot extension: `~/.vscode-server/data/User/globalStorage/github.copilot/`
## Acceptance
- [ ] Dockerfile creates `/home/agent/.config/github-copilot` directory
- [ ] Directory owned by agent user (UID 1000): `docker run --rm ... stat -c '%U' /home/agent/.config/github-copilot` outputs `agent`
- [ ] After Copilot CLI auth: `~/.config/github-copilot/hosts.json` contains token
- [ ] After container rebuild: `hosts.json` persists (volume not destroyed)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
