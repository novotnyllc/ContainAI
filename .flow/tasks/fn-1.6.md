# fn-1.6 Add GitHub Copilot and VS Code data volume mounts

## Description
Add volume mounts for GitHub Copilot authentication and VS Code extension data to persist across container rebuilds.

### Volume Mounts to Add

| Volume | Container Path | Purpose |
|--------|----------------|---------|
| `docker-github-copilot` | `/home/agent/.config/github-copilot` | Copilot CLI auth (`hosts.json`) |
| `docker-vscode-data` | `/home/agent/.config/Code` | VS Code globalStorage (Copilot tokens, extension state) |
| `docker-omnisharp` | `/home/agent/.omnisharp` | OmniSharp/C# Dev Kit configuration |

### GitHub Copilot Auth Locations

Per research, Copilot stores auth in:
- CLI: `~/.config/github-copilot/hosts.json` (OAuth tokens)
- VS Code: `~/.config/Code/User/globalStorage/github.copilot/` (extension tokens)
- VS Code: `~/.config/Code/User/globalStorage/github.copilot-chat/` (chat history)

### C# Dev Kit Locations

- OmniSharp config: `~/.omnisharp/omnisharp.json`
- Extension data: `~/.config/Code/User/globalStorage/ms-dotnettools.csdevkit/`

### Implementation

1. Update Dockerfile to create mount point directories:
   ```dockerfile
   RUN mkdir -p /home/agent/.config/github-copilot \
       /home/agent/.config/Code \
       /home/agent/.omnisharp \
       && chown -R agent:agent /home/agent/.config /home/agent/.omnisharp
   ```

2. Update devcontainer.json mounts array to include new volumes

3. Ensure proper permissions (agent user owns all directories)

### Reference

- Existing volume pattern: `claude/sync-plugins.sh:21-23`
- GitHub Copilot auth: `~/.config/github-copilot/hosts.json`
- VS Code globalStorage: `~/.config/Code/User/globalStorage/`
## Acceptance
- [ ] Dockerfile creates `/home/agent/.config/github-copilot` directory
- [ ] Dockerfile creates `/home/agent/.config/Code` directory
- [ ] Dockerfile creates `/home/agent/.omnisharp` directory
- [ ] All directories owned by agent user (UID 1000)
- [ ] devcontainer.json includes `docker-github-copilot` volume mount
- [ ] devcontainer.json includes `docker-vscode-data` volume mount
- [ ] devcontainer.json includes `docker-omnisharp` volume mount
- [ ] GitHub Copilot auth persists after container rebuild (if previously authenticated)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
