# Architecture Notes

## Container Design

### Base Image
- **OS**: Ubuntu 22.04 LTS
- **User**: `agentuser` (UID 1000, GID 1000)
- **Purpose**: Common foundation for all agent images
- **Size**: ~4GB
- **Lifespan**: Rarely changes

### Agent Images
- **Types**: copilot, codex, claude
- **Based on**: `coding-agents:local` (base image)
- **Size**: +10 MB each
- **Purpose**: Specialized validation and default commands

### Container Naming
- **Pattern**: `{agent}-{repo}-{branch}`
- **Branch sanitization**: `/` → `-`, lowercase, special chars removed
- **Examples**:
  - `copilot-myapp-main`
  - `codex-website-feature-auth`
  - `claude-api-develop`

## Branch Management

### Branch Isolation
**How agents interact with branches:**
- Without `--branch`: Auto-creates unique session branch `{agent}/session-N`
- With `--branch <name>`: Creates `{agent}/<name>` branch
- Already on agent branch (matches `{agent}/*`): Reuses that branch
- With `--use-current-branch`: Works directly on current branch

### Agent Branches
- Each agent works on isolated branch: `{agent}/{base-branch}`
- Examples: `copilot/feature-api`, `codex/refactor-db`, `copilot/session-1`
- Created automatically when launching agent
- Deleted automatically when container removed (unless has unmerged commits)

### Session Branches
- Auto-generated when no `--branch` specified
- Pattern: `{agent}/session-1`, `{agent}/session-2`, etc.
- Numbered sequentially to avoid conflicts
- Convenient for quick experiments without naming

### Conflict Resolution
1. **Detection**: Check for existing agent branch before creating
2. **Analysis**: Get unmerged commits vs base branch
3. **Decision**:
   - If unmerged commits exist: Archive with timestamp `{agent}/{branch}-archived-{timestamp}`
   - If no unmerged commits: Safe to delete
4. **User prompt**: Default is "No" (safe), `-y` flag auto-confirms

### Auto-archiving
Branches with unmerged work are automatically renamed:
- Pattern: `{agent}/{branch}-archived-{YYYYMMDD-HHMMSS}`
- Example: `copilot/main-archived-20241113-143022`
- Preserves work that hasn't been integrated

## Authentication

### OAuth Flow
- **No API keys stored anywhere**
- **GitHub**: Uses `gh` CLI authentication (mounted from `~/.config/gh`)
- **Copilot**: Uses GitHub Copilot subscription (mounted from `~/.config/github-copilot`)
- **Codex**: Uses codex CLI authentication (mounted from `~/.config/codex`)
- **Claude**: Uses Claude CLI authentication (mounted from `~/.config/claude`)

### MCP Secrets
- Stored in `~/.config/coding-agents/mcp-secrets.env` on host
- Mounted read-only at `/home/agentuser/.mcp-secrets.env` in container
- Contains API keys for MCP servers (Context7, GitHub, etc.)
- Not tracked in git, not baked into images

## Network Modes

### allow-all (Default)
- Full internet access
- Standard Docker bridge network
- Simplest, most compatible

### restricted
- No network access (`--network none`)
- Offline operation only
- For maximum isolation

### squid (Proxy with Whitelist)
- Squid proxy sidecar container
- Custom network for isolation
- Whitelisted domains:
  - `*.github.com`
  - `*.githubusercontent.com`
  - `*.nuget.org`
  - `*.npmjs.org`
  - `*.pypi.org`
- HTTP_PROXY env vars set automatically

## Dual Git Remotes

### local (Default)
- Points to original repository on host
- Path: `/workspace/.git` (inside container) → `{host-repo}/.git`
- Used for quick sync back to host
- Default push target (`git push` goes here)

### origin
- Points to GitHub (or other remote)
- Used for creating PRs
- Requires explicit `git push origin`
- Intentional publish to team

### Auto-push on Shutdown
- Enabled by default
- Checks for uncommitted changes on container exit
- Automatically commits and pushes to `local` remote
- Disable with `--no-push` flag or `AUTO_PUSH_ON_SHUTDOWN=false`

## MCP Server Configuration

### Config Flow
1. **Source**: `config.toml` (TOML format, single source of truth)
2. **Conversion**: `convert-toml-to-mcp.py` runs at container startup
3. **Output**: Agent-specific JSON configs:
   - `~/.config/github-copilot/mcp` → Copilot
   - `~/.config/codex/mcp` → Codex
   - `~/.config/claude/mcp` → Claude

### Per-Agent Customization
- **Serena context**: Codex uses "codex", others use "ide-assistant"
- **Modes**: All agents use "planning" and "editing" modes
- **Project**: Always `/workspace` (mounted repository)

### Available MCP Servers
- **GitHub**: Repository operations, issues, PRs
- **Microsoft Docs**: Official documentation search
- **Playwright**: Browser automation
- **Context7**: Code context retrieval
- **Serena**: Semantic code navigation and editing
- **Sequential Thinking**: Multi-step reasoning

## Container Labels

Every agent container has these labels:
```
coding-agents.type=agent
coding-agents.agent={copilot|codex|claude}
coding-agents.repo={repo-name}
coding-agents.branch={branch-name}
coding-agents.repo-path={absolute-path}
```

Optional labels (for proxy mode):
```
coding-agents.proxy-container={proxy-container-name}
coding-agents.proxy-network={network-name}
```

Test containers:
```
coding-agents.test=true
coding-agents.test-session={PID}
```

## Volume Mounts

### Read-Only (Host → Container)
- `~/.gitconfig` → `/home/agentuser/.gitconfig`
- `~/.config/gh` → `/home/agentuser/.config/gh`
- `~/.config/github-copilot` → `/home/agentuser/.config/github-copilot`
- `~/.config/codex` → `/home/agentuser/.config/codex`
- `~/.config/claude` → `/home/agentuser/.config/claude`
- `~/.config/coding-agents/mcp-secrets.env` → `/home/agentuser/.mcp-secrets.env`

### Read-Write
- `{repo-path}` → `/workspace` (agent's isolated copy)

## File Isolation

### Why Copy Instead of Mount?
- **Multiple agents**: Can work on same repo without conflicts
- **Isolation**: Changes isolated until explicitly pushed
- **No concurrent writes**: Safe from race conditions
- **Clean state**: Each agent gets fresh starting point

### Getting Changes Out
1. **Auto-push**: Default, pushes to `local` remote on exit
2. **Manual push**: `git push local` or `git push origin`
3. **VS Code**: Connect with Dev Containers, edit directly

## Security Principles

1. **OAuth over API keys**: All agent auth from mounted host credentials
2. **Isolation**: Each container independent filesystem
3. **No secrets in repo**: All auth mounted at runtime
4. **Stateless images**: No secrets or user data baked in
5. **Read-only mounts**: Host credentials mounted `:ro`
6. **Non-root user**: `agentuser` (UID 1000) in containers
7. **No new privileges**: `--security-opt no-new-privileges:true`

## Container Runtime Detection

### Auto-detection Order
1. Check `CONTAINER_RUNTIME` environment variable
2. If `docker` command available, use Docker
3. If `podman` command available, use Podman
4. Error if neither available

### Docker Desktop (Windows/Mac)
- Auto-start attempted (60s timeout)
- Machine initialization handled automatically

### Podman
- Machine must be initialized: `podman machine init`
- Machine must be started: `podman machine start`
- Compatible with Docker CLI commands
- BuildKit support native

## Agent Configuration Files

### Structure
```
agent-configs/
  AGENTS.md                    # Applies to all agents
  github-copilot/              # Copilot-specific
  codex/                       # Codex-specific
  claude/                      # Claude-specific
```

### Deployment
- Base `AGENTS.md` → All agent config directories
- `github-copilot/*` → `~/.config/github-copilot/agents/`
- `codex/*` → `~/.config/codex/instructions/`
- `claude/*` → `~/.config/claude/instructions/`

### Purpose
- Custom instructions for AI behavior
- Repository-specific guidance
- MCP tool descriptions
- Does not pollute user's workspace
