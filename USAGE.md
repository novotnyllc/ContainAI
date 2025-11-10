# Usage Guide

Quick guide for running AI coding agents in isolated containers.

## What You Need

### On Your Host Machine

1. **Docker** (with WSL2 on Windows)
2. **GitHub CLI** authenticated: `gh auth login`
3. **Git configured:**
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "your@email.com"
   ```

### Optional: Agent Authentication

- **GitHub Copilot**: Already handled by `gh auth login`
- **OpenAI Codex**: Setup OAuth, config at `~/.config/codex/`
- **Anthropic Claude**: Setup OAuth, config at `~/.config/claude/`

### Optional: MCP Server API Keys

If using MCP servers, create `~/.config/coding-agents/mcp-secrets.env`:

```bash
GITHUB_TOKEN=ghp_your_token_here
CONTEXT7_API_KEY=your_key_here
```

## Get the Images

### Option 1: Pull Pre-Built (Recommended)

```bash
docker pull ghcr.io/yourusername/coding-agents-copilot:latest
docker pull ghcr.io/yourusername/coding-agents-codex:latest
docker pull ghcr.io/yourusername/coding-agents-claude:latest
```

### Option 2: Build Locally

```bash
# Get the repository
git clone https://github.com/yourusername/coding-agents.git
cd coding-agents

# Build images
./scripts/build.sh  # Linux/Mac
.\scripts\build.ps1 # Windows
```

See [BUILD.md](BUILD.md) for details.

## Launch an Agent

The `launch-agent` script creates a persistent container with an isolated copy of your repository. The container runs in the background, allowing you to connect with VS Code Dev Containers extension.

### Basic Usage

**PowerShell (Windows):**
```powershell
.\launch-agent.ps1
```

**Bash (Linux/Mac/WSL):**
```bash
./launch-agent
```

This creates a container with a copy of your current repository.

### Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| Source (positional) | Local path or GitHub URL | `.`, `/path/to/repo`, `https://github.com/user/repo` |
| `-b` or `--branch` | Feature branch name (becomes `<agent>/<branch>`) | `-b auth` creates `copilot/auth` |
| `--agent` | Choose agent: `copilot`, `codex`, `claude`, `all` (default: `all`) | `--agent codex` |
| `--name` | Custom container name | `--name my-workspace` |
| `--dotnet-preview` | Install .NET preview SDK (e.g., `9.0`, `10.0`) | `--dotnet-preview 9.0` |
| `--network-proxy` | Network mode: `none` (default), `allow-all`, `squid` | `--network-proxy allow-all` |

**Network Proxy Modes:**
- `none` (default): Standard Docker network access
- `allow-all`: Explicitly allow all network traffic
- `squid`: Route through proxy for monitoring (not yet implemented)

See [NETWORK_PROXY.md](NETWORK_PROXY.md) for network configuration details.

## Examples

### From Specific Directory

```powershell
.\launch-agent.ps1 C:\projects\my-app
```

```bash
./launch-agent /home/user/projects/my-app
```

### Clone from GitHub

```powershell
.\launch-agent.ps1 https://github.com/user/repo
```

The repository is cloned into the container (isolated from host).

### Choose an Agent

```powershell
# GitHub Copilot
.\launch-agent.ps1 . --agent copilot

# OpenAI Codex
.\launch-agent.ps1 . --agent codex

# Anthropic Claude
.\launch-agent.ps1 . --agent claude

# All agents available
.\launch-agent.ps1 . --agent all
```

### Custom Branch

```powershell
.\launch-agent.ps1 . -b feature-auth --agent copilot
```

Creates and checks out branch: `copilot/feature-auth`

### Install .NET Preview SDK

```powershell
# Install .NET 9.0 preview
.\launch-agent.ps1 . --agent codex --dotnet-preview 9.0

# Install .NET 10.0 preview
.\launch-agent.ps1 . --agent codex --dotnet-preview 10.0
```

The preview SDK is installed at container startup and available alongside stable versions.

### Configure Network Access

```powershell
# Default (restricted mode)
.\launch-agent.ps1 .

# Allow all network traffic (unrestricted)
.\launch-agent.ps1 . --network-proxy allow-all

# Future: Squid proxy with monitoring (not yet implemented)
.\launch-agent.ps1 . --network-proxy squid
```

See [NETWORK_PROXY.md](NETWORK_PROXY.md) for detailed network configuration options.

## Multiple Agents, Same Repo

Launch multiple agents working on different features:

```powershell
.\launch-agent.ps1 C:\projects\app -b auth --agent copilot
.\launch-agent.ps1 C:\projects\app -b database --agent codex  
.\launch-agent.ps1 C:\projects\app -b ui --agent claude
```

Each agent gets:
- Own isolated workspace
- Own branch (`copilot/auth`, `codex/database`, `claude/ui`)
- Own container (`copilot-app`, `codex-app`, `claude-app`)

No conflicts!

## Connect from VS Code

Containers run in the background. Connect anytime:

1. Install **Dev Containers** extension
2. Click remote button (bottom-left)
3. Select "Attach to Running Container"
4. Choose your container (e.g., `copilot-app`)

Or via command line:
```bash
docker exec -it copilot-app bash
```

## Inside the Container

### Repository Location

Your code is at `/workspace`:
```bash
cd /workspace
ls -la
```

### Git Workflow

Two remotes are configured:

```bash
git remote -v
# origin: GitHub (for pull requests)
# local:  Host machine (default push)
```

**Push to host (default):**
```bash
git push
```

**Push to GitHub:**
```bash
git push origin
```

**Pull from host:**
```bash
git pull local main
```

**Pull from GitHub:**
```bash
git pull origin main
```

### MCP Configuration

If your workspace has `config.toml`, it's automatically converted to agent-specific JSON on container startup.

**Example config.toml:**
```toml
[mcp_servers.github]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]

[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp"]
env = { CONTEXT7_API_KEY = "${CONTEXT7_API_KEY}" }
```

Secrets like `CONTEXT7_API_KEY` are loaded from `~/.config/coding-agents/mcp-secrets.env` (if mounted).

## Container Management

### List Containers

```bash
docker ps              # Running
docker ps -a           # All (including stopped)
```

### Stop Container

```bash
docker stop copilot-app
```

### Start Existing Container

```bash
docker start copilot-app
# or
.\launch-agent.ps1     # Auto-detects and starts existing
```

### Remove Container

```bash
docker rm -f copilot-app
```

⚠️ **Warning:** This deletes the container's workspace. Push your changes first!

### Container Logs

```bash
docker logs copilot-app
```

## Troubleshooting

### Authentication Warnings

If you see:
```
⚠️ WARNING: GitHub Copilot authentication not found!
```

**Solution:**
1. Run `gh auth login` on your host
2. Restart container: `docker restart copilot-app`

### MCP Servers Not Working

Check secrets file exists:
```bash
ls ~/.config/coding-agents/mcp-secrets.env
```

Verify tokens are valid:
- GitHub: https://github.com/settings/tokens
- Context7: https://context7.ai/

Restart container after adding/updating secrets.

### Container Already Exists

If you see "Container already exists":
```bash
# Remove old container
docker rm -f copilot-app

# Launch again
.\launch-agent.ps1
```

### Git Push Fails

```bash
# Check remotes
git remote -v

# Check which remote is default
git config remote.pushDefault

# Set explicitly
git push local copilot/feature-auth
# or
git push origin copilot/feature-auth
```

### Can't Connect from VS Code

1. Ensure container is running: `docker ps`
2. Install **Dev Containers** extension (ms-vscode-remote.remote-containers)
3. Try attaching with Docker extension instead

## Advanced Usage

### Custom Container Name

```powershell
.\launch-agent.ps1 . --name experiment-1
# Creates: all-experiment-1
```

### Specify Git Remote Manually

Edit inside container:
```bash
git remote add upstream https://github.com/upstream/repo.git
git fetch upstream
```

### Use docker-compose (Advanced)

```bash
# Create .env
cp .env.example .env

# Start services
REPO_PATH=/path/to/repo docker-compose up -d

# Connect
docker exec -it coding-agent bash
```

Most users should use `launch-agent` instead.

## What Happens Behind the Scenes

When you run `launch-agent`:

1. **Detects source:**
   - Local path: Copies entire repo into container
   - GitHub URL: Clones repo into container

2. **Creates container:**
   - Mounts OAuth configs from host (read-only)
   - Runs in background (persistent)
   - Creates workspace at `/workspace`

3. **Setups git:**
   - Sets `origin` remote (GitHub)
   - Sets `local` remote (host path, if applicable)
   - Sets `local` as default push target
   - Configures gh CLI for credentials

4. **Creates branch:**
   - Checks out `<agent>/<branch-name>`
   - Example: `copilot/feature-auth`

5. **Loads MCP config:**
   - Looks for `/workspace/config.toml`
   - Converts to agent-specific JSON
   - Loads secrets from `~/.mcp-secrets.env`

6. **Ready:**
   - Container runs in background
   - Connect via VS Code or shell

## Security Notes

✅ **Safe:**
- OAuth authentication (no hardcoded API keys)
- Read-only mounts from host
- Non-root user in container
- No secrets in repository
- No secrets in container images
- Isolated filesystem per container

⚠️ **Keep secure:**
- `~/.config/coding-agents/mcp-secrets.env` (outside any git repo)
- Don't commit `.env` files with real tokens

## Command Reference

### Launch Agent
```powershell
# PowerShell
.\launch-agent.ps1 [source] [-Branch name] [-Agent type] [-Name custom]

# Bash
./launch-agent [source] [-b name] [--agent type] [--name custom]
```

**Parameters:**
- `source`: Directory path or GitHub URL (default: current dir)
- `-Branch`/`-b`: Branch name (default: current branch or "main")
- `-Agent`/`--agent`: copilot, codex, claude, all (default: all)
- `-Name`/`--name`: Custom container name (default: auto-generated)

### Docker Commands
```bash
docker ps                          # List running containers
docker ps -a                       # List all containers
docker stop <container>            # Stop container
docker start <container>           # Start container
docker restart <container>         # Restart container
docker rm -f <container>           # Remove container (loses workspace!)
docker logs <container>            # View logs
docker exec -it <container> bash   # Open shell
```

## Examples

### Single agent, quick task

```powershell
.\launch-agent.ps1 . --agent copilot
# Work in container
# Push changes
docker rm -f copilot-myrepo
```

### Long-term development

```powershell
.\launch-agent.ps1 C:\projects\app -b feature-x --agent copilot
# Connect from VS Code
# Work over days/weeks
# Container persists until you remove it
```

### Multiple features, multiple agents

```powershell
.\launch-agent.ps1 . -b backend --agent copilot
.\launch-agent.ps1 . -b frontend --agent claude
.\launch-agent.ps1 . -b tests --agent codex
```

### Experiment with open source

```powershell
.\launch-agent.ps1 https://github.com/microsoft/vscode -b explore --agent copilot
# Explore in isolated environment
# No impact on host
docker rm -f copilot-vscode  # Clean up when done
```

## FAQ

**Q: Do I need to build the images myself?**  
A: No if using published images. Yes if making custom changes.

**Q: Where are my changes stored?**  
A: Inside the container at `/workspace`. They're persistent until you remove the container.

**Q: How do I get my changes out?**  
A: Use `git push` (pushes to `local` remote on host by default) or `git push origin` (pushes to GitHub).

**Q: Can I edit files from host while container is running?**  
A: No, the workspace is isolated inside the container. Use VS Code Remote to edit.

**Q: What if I accidentally delete the container?**  
A: If you pushed your changes to git, you can recover. Otherwise, they're lost. Always push!

**Q: Do all agents see the same code?**  
A: No, each container has its own isolated copy of the repository.

**Q: How much disk space do containers use?**  
A: Images: ~4GB base + 100MB per agent. Containers: depends on your code size.

**Q: Can I use this without VS Code?**  
A: Yes, use `docker exec -it <container> bash` for a terminal.

---

**Next Steps:**
- See [BUILD.md](BUILD.md) if building images yourself
- See [ARCHITECTURE.md](ARCHITECTURE.md) for system design
