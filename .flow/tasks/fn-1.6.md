# fn-1.6 Add volume mount points in Dockerfile

## Description
Create mount point directories in Dockerfile for volumes (per spec Volume Strategy).

### Mount Points to Create

| Volume | Container Path | Purpose |
|--------|----------------|---------|
| `dotnet-sandbox-vscode` | `/home/agent/.vscode-server` | VS Code server data + Copilot extension auth |
| `dotnet-sandbox-nuget` | `/home/agent/.nuget` | NuGet package cache |
| `dotnet-sandbox-gh` | `/home/agent/.config/gh` | GitHub CLI config |
| `docker-claude-plugins` | `/home/agent/.claude/plugins` | Claude plugins (reused from existing) |

**Note**: `docker-claude-sandbox-data` is managed by docker sandbox / sync-plugins.sh - we do NOT create this mount point (symlink handles credentials).

### Implementation

1. Update Dockerfile to create mount point directories:
   ```dockerfile
   RUN mkdir -p /home/agent/.vscode-server \
               /home/agent/.nuget \
               /home/agent/.config/gh \
               /home/agent/.claude/plugins \
       && chown -R agent:agent /home/agent/.vscode-server \
                               /home/agent/.nuget \
                               /home/agent/.config \
                               /home/agent/.claude
   ```

2. Ensure proper permissions (agent user owns directories)
## Acceptance
- [x] Dockerfile creates `/home/agent/.vscode-server` directory
- [x] Dockerfile creates `/home/agent/.nuget` directory
- [x] Dockerfile creates `/home/agent/.config/gh` directory
- [x] Dockerfile creates `/home/agent/.claude/plugins` directory
- [x] All directories owned by agent user (UID 1000)
- [x] Directories have correct permissions
## Done summary
- Added mount point directories in Dockerfile for volume mounts
- Created /home/agent/.vscode-server, .nuget, .config/gh, .claude/plugins
- Set correct ownership (agent:agent) for all directories

Why:
- Volumes require pre-existing mount points with correct permissions
- Per Volume Strategy in epic spec

Verification:
- Dockerfile syntax verified by code review
- Docker build cannot be tested (daemon not available in CI)
- All acceptance criteria addressed in implementation
## Evidence
- Commits: 4bd004b6afbe5b1de32340943d227201066441ce
- Tests: Dockerfile syntax review
- PRs: