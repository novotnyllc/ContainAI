# VS Code Integration Guide

This guide shows how to use Visual Studio Code to work with agent containers, including connecting to running instances, starting new containers, and interacting with the agent workspace.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Connecting to a Running Container](#connecting-to-a-running-container)
- [Starting a New Container from VS Code](#starting-a-new-container-from-vs-code)
- [Working Inside the Container](#working-inside-the-container)
- [Interacting with the Agent](#interacting-with-the-agent)
- [Advanced Workflows](#advanced-workflows)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Extensions

Install the **Dev Containers** extension (formerly Remote - Containers):

1. Open VS Code
2. Press `Ctrl+Shift+X` (or `Cmd+Shift+X` on macOS)
3. Search for "Dev Containers"
4. Install **Dev Containers** by Microsoft (`ms-vscode-remote.remote-containers`)

**Alternative:** Install from command line:
```bash
code --install-extension ms-vscode-remote.remote-containers
```

### Required Tools

- Docker 20.10+ (Docker Desktop or Docker Engine) running and accessible
- VS Code 1.80+
- Git (for repository operations)

**Verify installation:**
```powershell
# Check Docker
docker --version

Agent data lives under `/run/agent-data/<agent>/<session>/home` with read/write permissions only for `agentcli`. `agentuser` interacts with it via symlinks (`~/.copilot`, `~/.codex`, `~/.claude`) that point into that tmpfs. This prevents host bind mounts from exposing user secrets or history files. Inspect the mount options to confirm:
```bash
 agentuser@container:/workspace$ findmnt /run/agent-data
 TARGET           SOURCE FSTYPE OPTIONS
 /run/agent-data  tmpfs  tmpfs  rw,nosuid,nodev,noexec,mode=0770,private
 ```
# Check VS Code version
code --version

# Check Dev Containers extension
code --list-extensions | Select-String "ms-vscode-remote.remote-containers"
```

---

## Quick Start

### Method 1: Launch Agent, Then Attach VS Code

1. **Start an agent container (pick the channel-specific launcher name):**
   ```powershell
   # Windows PowerShell
   .\host\launchers\entrypoints\run-copilot-dev.ps1  # dev clone
   .\host\launchers\entrypoints\run-copilot.ps1      # prod bundle
   .\host\launchers\entrypoints\run-copilot-nightly.ps1 # nightly smoke
   
   # Or bash (Git Bash, WSL)
   ./host/launchers/entrypoints/run-copilot-dev
   ```

2. **Attach VS Code:**
   - Press `F1` (or `Ctrl+Shift+P`)
   - Type: `Dev Containers: Attach to Running Container...`
   - Select your container (e.g., `copilot-agent`)

3. **Open workspace:**
   - Once connected, click **File → Open Folder**
   - Navigate to: `/workspace`
   - Click **OK**

**Result:** VS Code Explorer shows your repository files from inside the container.

### Method 2: Launch from VS Code's Integrated Terminal

1. **Open VS Code on the host** (outside of any container) and load the ContainAI repository so the launchers are on your PATH.
2. **Open the integrated terminal:** `` Ctrl+` ``.
3. **Run a launcher from your project directory (dev/prod/nightly as needed):**
   ```bash
   cd ~/my-project
    run-copilot-dev        # or run-codex-dev / run-claude-dev
   ```
4. **Attach VS Code** using the steps in Method 1 once the container is running.

---

## Connecting to a Running Container

### Find Running Containers

**From VS Code:**
1. Click the **Remote Explorer** icon in the Activity Bar (left sidebar)
   - Icon looks like: 🖥️ (monitor/screen)
2. From the dropdown at the top, select: **Dev Containers**
3. You'll see all running containers listed

**From Terminal:**
```powershell
# List all running containers
docker ps

# Filter agent containers
docker ps --filter "name=agent"
```

### Attach to Container

**Option A: Via Remote Explorer**
1. Open **Remote Explorer** (Activity Bar → Dev Containers)
2. Hover over the container name (e.g., `copilot-agent`)
3. Click the **➡️ arrow** icon ("Attach in New Window")
4. VS Code opens a new window connected to the container

**Option B: Via Command Palette**
1. Press `F1` or `Ctrl+Shift+P`
2. Type: `Dev Containers: Attach to Running Container...`
3. Select your container from the list
4. VS Code opens connected to the container

**Option C: Quick Action**
1. Click the **Remote Indicator** in the bottom-left corner
   - Shows: `><` icon with "Local" or current connection
2. Select: `Attach to Running Container...`
3. Choose your container

### Open the Workspace

After attaching to the container:

1. **File → Open Folder** (or `Ctrl+K Ctrl+O`)
2. Navigate to: `/workspace`
3. Click **OK** or **Open**

**Result:** The Explorer pane shows your repository files as they exist inside the container.

---

## Starting a New Container from VS Code

### Method 1: Using the Host Integrated Terminal

For full control over launch options:

1. **Open integrated terminal:** `` Ctrl+` `` (backtick)
2. **Navigate to repository root:**
   ```powershell
   cd e:\dev\ContainAI
   ```

3. **Launch with options:**
   ```powershell
   # Basic launch
   .\host\launchers\entrypoints\run-copilot-dev.ps1
   
   # With custom resources
   .\host\launchers\entrypoints\run-copilot-dev.ps1 --cpu 8 --memory 16g
   
   # With branch isolation
   .\host\launchers\entrypoints\run-copilot-dev.ps1 --branch feature/new-api
   
   # With custom name
   .\host\launchers\entrypoints\run-copilot-dev.ps1 --name my-experiment
   ```

4. **Attach VS Code** (see [Connecting to a Running Container](#connecting-to-a-running-container))

### Method 2: Direct Docker Command

For advanced users:

```powershell
# Using launch-agent script directly
.\host\launchers\launch-agent.ps1 `
  --agent copilot `
  --cpu 4 `
  --memory 8g `
  --name my-copilot-instance

# Then attach VS Code
```

See [CLI Reference](cli-reference.md) for all available options.

---

## Working Inside the Container

### Understanding the Environment

When VS Code is attached to a container:

- **Workspace:** `/workspace` (your repository root inside the container)
- **Home:** `/home/agentuser` (workspace user home directory)
- **Config:** `/home/agentuser/.config/` (MCP and agent configurations)
- **CLI user:** `agentcli` (non-login account that owns `/run/agent-secrets` and `/run/agent-data`)
- **Extensions:** VS Code extensions run inside the container (optional)

**Visual Indicators:**
- Bottom-left corner shows: `Dev Container: copilot-agent` (or container name)
- Terminal prompt shows: `agentuser@<container-id>:/workspace$`
- Explorer shows files from `/workspace`

### File Explorer

The Explorer pane (`Ctrl+Shift+E`) shows your repository as it exists inside the container:

```
/workspace/
├── .git/                    # Git repository data
├── agent-configs/           # Agent instruction files
├── docker/                  # Container definitions
├── scripts/                 # Launcher and utility scripts
├── docs/                    # Documentation
├── config.toml              # MCP configuration template
├── README.md
└── CONTRIBUTING.md
```

**File Operations:**
- **Edit files:** Click any file to open in editor
- **Create files:** Right-click → New File
- **Delete files:** Right-click → Delete
- **Search files:** `Ctrl+P` for Quick Open, `Ctrl+Shift+F` for search

**Changes persist** because `/workspace` is mounted from your host repository.

### Integrated Terminal

**Open terminal:** `` Ctrl+` `` or **Terminal → New Terminal**

The terminal runs **inside the container** as `agentuser`:

```bash
agentuser@abc123:/workspace$ pwd
/workspace

agentuser@abc123:/workspace$ whoami
agentuser
agentuser@abc123:/workspace$ id -nG
agentuser agentcli

agentuser@abc123:/workspace$ which gh
/usr/bin/gh
```

**Available tools inside container:**
- Git, GitHub CLI (`gh`)
- Node.js, npm, npx
- .NET SDK (if using .NET preview)
- Python (depending on agent image)
- Container runtime client (Docker-in-Docker)

**Common terminal operations:**
```bash
# Git operations
git status
git log --oneline -10
git branch

# Check MCP configuration
cat ~/.config/mcp.json

# View agent logs (if available)
cat /tmp/agent-*.log

# Check environment
env | grep -i token
```

### Source Control

The **Source Control** pane (`Ctrl+Shift+G`) integrates with Git inside the container:

- **View changes:** See modified, staged, and untracked files
- **Stage changes:** Click `+` icon next to files
- **Commit:** Enter commit message and click ✓ (checkmark)
- **Push/Pull:** Use `...` menu → Push/Pull

**Git configuration:**
- Uses Git config from mounted workspace (`.git/config`)
- SSH keys via forwarded `SSH_AUTH_SOCK` (host `~/.ssh` is never mounted)
- GitHub CLI authentication (if configured)

### Extensions

VS Code extensions can run either on your **local machine** or **inside the container**.

**Local extensions** (run on host):
- Themes, keymaps, UI customizations
- Git Graph, GitLens (can work remotely)

**Remote extensions** (run in container):
- Language servers (C#, Python, JavaScript)
- Linters, formatters (ESLint, Prettier, Black)
- Debuggers

**Installing extensions in container:**
1. Open Extensions pane (`Ctrl+Shift+X`)
2. Search for an extension
3. Click **Install in Dev Container: copilot-agent**
   - Note the "Install in Dev Container" button (not just "Install")

**Recommended extensions for containers:**
- **C# Dev Kit** (for .NET projects)
- **Python** (for Python projects)
- **ESLint** (for JavaScript/TypeScript)
- **Docker** (for container management)
- **GitHub Copilot** (if you have access)

---

## Interacting with the Agent

### Understanding the Agent Architecture

Agents run as **interactive shell sessions** inside the container. When you launch an agent, it starts a persistent session that you can interact with.

**Agent startup process:**
1. Container starts with environment configured
2. MCP servers are initialized (GitHub, Microsoft Docs, Playwright, etc.)
3. Agent shell session begins
4. Agent waits for user input

### Checking Agent Status

**Method 1: Check running processes**
```bash
# Inside container terminal
ps aux | grep -E "agent|copilot|claude|codex"

# Look for process like:
# agentuser  123  0.0  0.1  12345  6789 ?  S  10:00  0:00  gh copilot
```

**Method 2: Check container logs**
```powershell
# From host (outside container)
docker logs copilot-agent

# Shows startup messages and agent initialization
```

**Method 3: VS Code terminal**
- If agent is running interactively, you'll see its prompt
- Example (GitHub Copilot): Agent responds to commands like `gh copilot suggest "..."`

### Interacting via Terminal

**For GitHub Copilot:**
```bash
# In VS Code terminal (inside container)
gh copilot suggest "How do I list files recursively in PowerShell?"

gh copilot explain "What does this regex do: ^[a-z0-9]+$"

# Interactive chat mode
gh copilot
# Then type questions directly
```

**For other agents (if configured):**
```bash
# Example: API-based agents might have CLI commands
agent-cli chat "Explain the observer pattern"

# Or agents might watch for files
echo "Refactor the User class to use dependency injection" > /tmp/agent-task.txt
```

### Interacting via Files

Some agents can be configured to watch for task files:

**Example workflow:**
1. **Create a task file:**
   ```bash
   # In VS Code terminal
   echo "Add unit tests for the calculate() function" > /workspace/.agent-tasks/task-001.md
   ```

2. **Agent processes the task:**
   - Reads the task file
   - Executes the requested changes
   - Writes results to output file or directly modifies code

3. **Review changes:**
   - Check Source Control pane for modifications
   - Review generated files in Explorer

**Note:** File-based interaction depends on agent configuration and may require custom setup.

### Interacting via VS Code Extensions

**GitHub Copilot Extension:**

If you have the GitHub Copilot extension installed:

1. **Chat panel:** `Ctrl+Shift+I` (or click Copilot icon in Activity Bar)
2. **Inline suggestions:** Type code, Copilot suggests completions (Tab to accept)
3. **Explain code:** Select code → Right-click → Copilot → Explain
4. **Generate tests:** Select function → Right-click → Copilot → Generate Tests

**Extension uses agent's MCP context:**
- GitHub MCP server provides repository access
- Microsoft Docs MCP provides documentation
- Agent environment includes all configured tools

### Common Agent Tasks

**1. Code Generation:**
```bash
# Via terminal (GitHub Copilot)
gh copilot suggest "Create a PowerShell function to parse JSON and extract nested values"

# Copy the output and paste into a file in VS Code
```

**2. Code Explanation:**
- Select code in editor
- Run: `gh copilot explain` (if terminal-based)
- Or use Copilot extension right-click menu

**3. Debugging Help:**
```bash
# Share error message with agent
gh copilot suggest "How do I fix this error: 'Cannot bind argument to parameter Path because it is an empty string'"

# Agent provides troubleshooting steps
```

**4. Code Review:**
```bash
# Have agent review a file
gh copilot suggest "Review this C# file for best practices: $(cat ./src/UserService.cs)"

# Agent provides feedback
```

**5. Documentation:**
```bash
# Generate documentation
gh copilot suggest "Write XML documentation comments for this C# class: $(cat ./src/Models/User.cs)"

# Agent generates doc comments
```

### Monitoring Agent Activity

**Container logs:**
```powershell
# From host terminal
docker logs -f copilot-agent

# Shows real-time agent output
# Press Ctrl+C to stop following
```

**MCP server logs:**
```bash
# Inside container
ls -la /tmp/mcp-*.log
cat /tmp/mcp-github.log
cat /tmp/mcp-serena.log
```

**Resource usage:**
```powershell
# From host
docker stats copilot-agent

# Shows CPU, memory, network, I/O in real-time
# Press Ctrl+C to stop
```

---

## Advanced Workflows

### Multiple Containers

You can run multiple agent containers simultaneously and switch between them in VS Code.

**Example: Run Copilot and Claude in parallel**

1. **Start first agent:**
   ```powershell
   .\host\launchers\entrypoints\run-copilot-dev.ps1 --name copilot-main
   ```

2. **Start second agent:**
   ```powershell
   .\host\launchers\entrypoints\run-claude-dev.ps1 --name claude-experiment
   ```

3. **Switch between containers in VS Code:**
   - Click **Remote Indicator** (bottom-left `><` icon)
   - Select: `Attach to Running Container...`
   - Choose `copilot-main` or `claude-experiment`

**Use case:** Compare agent responses, test different configurations, or isolate experiments.

### Branch Isolation

Work on different branches in separate containers:

```powershell
# Container for main branch
.\host\launchers\entrypoints\run-copilot-dev.ps1 --name copilot-main

# Container for feature branch
.\host\launchers\entrypoints\run-copilot-dev.ps1 --branch feature/api-refactor --name copilot-feature

# Container for experiment (current branch)
.\host\launchers\entrypoints\run-copilot-dev.ps1 --use-current-branch --name copilot-experiment
```

**VS Code workflow:**
1. Attach to `copilot-main` → work on main branch
2. Attach to `copilot-feature` → work on feature branch
3. Changes in each container are isolated

**Note:** Containers share the same workspace mount, so uncommitted changes are visible across containers. Commit or stash changes before switching branches.

### Custom Resource Allocation

Allocate more resources for heavy workloads:

```powershell
# High-performance configuration
.\host\launchers\entrypoints\run-copilot-dev.ps1 `
  --cpu 8 `
  --memory 16g `
  --name copilot-perf

# GPU support (if available)
.\host\launchers\entrypoints\run-copilot-dev.ps1 `
  --cpu 8 `
  --memory 16g `
  --gpu all `
  --name copilot-gpu
```

**Monitor resource usage in VS Code:**
- Open terminal: `` Ctrl+` ``
- Run: `docker stats copilot-perf`

### Port Forwarding

If the agent runs a web server or API:

**Method 1: Automatic forwarding (VS Code)**
1. Agent starts server on port (e.g., 3000)
2. VS Code detects the port
3. Notification appears: "Your application running on port 3000 is available"
4. Click **Open in Browser**

**Method 2: Manual forwarding**
1. Open Command Palette: `F1`
2. Type: `Forward a Port`
3. Enter port number (e.g., `3000`)
4. Access via `http://localhost:3000`

**Method 3: Via launch script**
```powershell
# Add port mapping when launching
docker run -p 3000:3000 containai/copilot:latest
```

### Debugging Inside Container

Set up debugging for code running inside the container:

**For .NET (C#):**
1. Install **C# Dev Kit** extension in container
2. Open Command Palette → `.NET: Generate Assets for Build and Debug`
3. Set breakpoints in code (click left gutter)
4. Press `F5` to start debugging

**For Python:**
1. Install **Python** extension in container
2. Create `.vscode/launch.json`:
   ```json
   {
     "version": "0.2.0",
     "configurations": [
       {
         "name": "Python: Current File",
         "type": "debugpy",
         "request": "launch",
         "program": "${file}",
         "console": "integratedTerminal"
       }
     ]
   }
   ```
3. Set breakpoints
4. Press `F5`

**For Node.js/JavaScript:**
1. Install **JavaScript Debugger** (built-in)
2. Add debug configuration
3. Set breakpoints
4. Press `F5`

### Persistent Configuration

Save VS Code settings specific to the container:

**Workspace settings** (`.vscode/settings.json`):
```json
{
  "terminal.integrated.defaultProfile.linux": "bash",
  "files.watcherExclude": {
    "**/.git/objects/**": true,
    "**/node_modules/**": true
  },
  "git.autofetch": true,
  "editor.formatOnSave": true
}
```

**Extensions** (`.vscode/extensions.json`):
```json
{
  "recommendations": [
    "ms-dotnettools.csdevkit",
    "ms-python.python",
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode"
  ]
}
```

These settings are committed to the repository and apply to all developers working in containers.

### Stopping and Cleaning Up

**Stop container (preserves container):**
```powershell
# From host terminal
docker stop copilot-agent

# VS Code connection closes automatically
```

**Remove container:**
```powershell
# Remove stopped container
docker rm copilot-agent

# Stop and remove in one command
docker rm -f copilot-agent
```

**Clean up all agent containers:**
```powershell
# List agent containers
docker ps -a --filter "name=agent"

# Remove all stopped agent containers
docker container prune --filter "label=coding-agent=true"
```

---

## Troubleshooting

### Can't See Container in Remote Explorer

**Symptom:** Dev Containers section is empty or missing containers.

**Solutions:**

1. **Refresh the view:**
   - Right-click in Remote Explorer → Refresh
   - Or reload VS Code: `Ctrl+Shift+P` → `Developer: Reload Window`

2. **Check container is running:**
   ```powershell
   docker ps --filter "name=agent"
   ```

3. **Verify Dev Containers extension:**
   ```powershell
   code --list-extensions | Select-String "remote-containers"
   ```
   - If missing, reinstall: `code --install-extension ms-vscode-remote.remote-containers`

4. **Check Docker socket access:**
   ```powershell
   docker info
   ```
   - If error, ensure Docker is running

### VS Code Can't Attach to Container

**Symptom:** "Failed to connect to the remote extension host server" or similar error.

**Solutions:**

1. **Container must be running:**
   ```powershell
   docker ps --filter "name=copilot-agent"
   ```

2. **Check container is healthy:**
   ```powershell
   docker inspect copilot-agent --format '{{.State.Status}}'
   # Should show: running
   ```

3. **Container needs a long-running process:**
   - ContainAI containers use `sleep infinity` or interactive shell
   - Verify: `docker logs copilot-agent` (should not show immediate exit)

4. **Restart VS Code:**
   - Close all VS Code windows
   - Reopen and try attaching again

### Files Not Visible in Explorer

**Symptom:** `/workspace` folder is empty or missing files.

**Solutions:**

1. **Open the correct folder:**
   - File → Open Folder → `/workspace` (not `/home/agentuser`)

2. **Check workspace is mounted:**
   ```bash
   # Inside container terminal
   ls -la /workspace
   
   # Should show repository files
   ```

3. **Verify mount from host:**
   ```powershell
   # From host
   docker inspect copilot-agent --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
   
   # Should show: E:\dev\ContainAI -> /workspace
   ```

4. **Check file permissions:**
   ```bash
   # Inside container
   stat /workspace
   # Owner should be: agentuser or accessible to agentuser
   ```

### Terminal Shows Host Instead of Container

**Symptom:** Terminal prompt shows host username, not `agentuser@container`.

**Solution:**

- **Check Remote Indicator:** Bottom-left corner should show `Dev Container: copilot-agent`
- **If it shows "Local":**
  1. Close terminal: Right-click terminal tab → Kill Terminal
  2. Open new terminal: `` Ctrl+` ``
  3. Should now show container prompt

### Extensions Not Working in Container

**Symptom:** Language features, linting, or formatting not working.

**Solutions:**

1. **Install extension in container:**
   - Extensions pane → Search for extension
   - Click **Install in Dev Container** (not just "Install")

2. **Reload window:**
   - `Ctrl+Shift+P` → `Developer: Reload Window`

3. **Check extension host:**
   - `Ctrl+Shift+P` → `Developer: Show Running Extensions`
   - Ensure extensions show "Remote" location

4. **Install dependencies:**
   - Some extensions need tools in container (e.g., Python extension needs `python`)
   - Install via terminal: `apt-get install python3` (if needed)

### Git Operations Fail

**Symptom:** "Could not resolve host 'github.com'" or authentication errors.

**Solutions:**

1. **Check network connectivity:**
   ```bash
   # Inside container
   ping -c 3 github.com
   ```

2. **Verify Git is configured:**
   ```bash
   git config --global user.name
   git config --global user.email
   ```

3. **Check GitHub CLI authentication:**
   ```bash
   # Run on the host (outside the container)
   gh auth status
   
   # If not authenticated (still on the host):
   gh auth login
   ```

4. **SSH key access:**
   - Host `~/.ssh` is intentionally never mounted for security
   - Ensure `ssh-agent` is running so `SSH_AUTH_SOCK` can be forwarded, or use HTTPS with GitHub CLI

### Container Stops Unexpectedly

**Symptom:** Container exits shortly after starting.

**Solutions:**

1. **Check container logs:**
   ```powershell
   docker logs copilot-agent
   ```

2. **Verify launch command:**
   - Container must have a long-running process
   - Check Dockerfile: `CMD ["sleep", "infinity"]` or interactive shell

3. **Resource limits:**
   - Container may be OOM-killed if memory limit too low
   - Increase: `--memory 16g`

4. **Manual start with interactive shell:**
   ```powershell
   docker run -it --rm `
     --name copilot-debug `
     -v E:\dev\ContainAI:/workspace `
     containai/copilot:latest `
     /bin/bash
   
   # Debug inside container
   ```

### Performance Issues

**Symptom:** VS Code is slow, unresponsive, or file operations lag.

**Solutions:**

1. **Increase container resources:**
   ```powershell
   # Stop and restart with more resources
   docker stop copilot-agent
   .\scripts\launchers\run-copilot.ps1 --cpu 8 --memory 16g
   ```

2. **Exclude file watchers:**
   - Add to `.vscode/settings.json`:
     ```json
     {
       "files.watcherExclude": {
         "**/.git/objects/**": true,
         "**/node_modules/**": true,
         "**/dist/**": true,
         "**/build/**": true
       }
     }
     ```

3. **Reduce extension load:**
   - Disable unnecessary extensions in container
   - Extensions → Disable (Remote)

4. **Check Docker performance:**
   ```powershell
   docker stats copilot-agent
   ```
   - High CPU/memory usage? Consider resource limits

5. **Use named volumes for node_modules:**
   - Avoid mounting `node_modules` from host (slow on Windows)
   - Use container-local volume instead

---

## Summary

You now know how to:

✅ **Install** the Dev Containers extension  
✅ **Connect** VS Code to running agent containers  
✅ **Launch** new containers from VS Code  
✅ **Navigate** the container filesystem in Explorer  
✅ **Execute** commands in the container terminal  
✅ **Interact** with ContainAI via terminal and extensions  
✅ **Work** with Git and source control inside containers  
✅ **Debug** code running in containers  
✅ **Troubleshoot** common VS Code container issues  

**Next steps:**
- [CLI Reference](cli-reference.md) - All launcher script options
- [MCP Setup](mcp-setup.md) - Configure additional MCP servers
- [Troubleshooting](TROUBLESHOOTING.md) - General troubleshooting guide

**Quick reference card:**

| Task | Command |
|------|---------|
| Attach to container | `F1` → "Attach to Running Container" |
| Open workspace | File → Open Folder → `/workspace` |
| New terminal | `` Ctrl+` `` |
| Launch agent | Open host terminal → `run-copilot` / `launch-agent` |
| Check logs | `docker logs copilot-agent` |
| Stop container | `docker stop copilot-agent` |
| Remote indicator | Bottom-left `><` icon |

Happy coding with your AI agent! 🚀
