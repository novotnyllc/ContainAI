# Quickstart Guide

Get from zero to your first AI sandbox in under 5 minutes.

## Prerequisites

Before starting, ensure you have:

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| Docker | Desktop 4.50+ or Engine 24.0+ | `docker --version` |
| Bash shell | 4.0+ | `echo "${BASH_VERSION}"` |
| Git | Any | `git --version` |

> **Shell note:** ContainAI requires **bash 4.0+**. If you use zsh, fish, or another shell, run `bash` first. macOS ships with bash 3.2; install a newer version via Homebrew (`brew install bash`).

## Step 1: Clone the Repository

```bash
git clone https://github.com/novotnyllc/containai.git
cd containai
```

**Verify:**
```bash
ls src/containai.sh
# Should show: src/containai.sh
```

## Step 2: Source the CLI

```bash
source src/containai.sh
```

**Verify:**
```bash
cai --help | head -3
# Should show:
# ContainAI - Run AI coding agents in a secure Docker sandbox
#
# Usage: containai [subcommand] [options]
```

> **Note:** You must source the script (not execute it) to add the `cai` command to your shell. Add this to your `~/.bashrc` for persistence.

## Step 3: Check Your Environment

Run the doctor command to detect your system's capabilities:

```bash
cai doctor
```

**What to look for:**

| Output | Meaning | Action |
|--------|---------|--------|
| `Sysbox: [OK]` | Sysbox runtime configured | Ready to go! |
| `Sysbox: [ERROR]` | No isolation available | Install Sysbox (see below) |

### Runtime Decision Tree

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {
  'primaryColor': '#1a1a2e',
  'primaryTextColor': '#ffffff',
  'primaryBorderColor': '#16213e',
  'secondaryColor': '#0f3460',
  'tertiaryColor': '#1a1a2e',
  'lineColor': '#a0a0a0',
  'textColor': '#ffffff',
  'background': '#0d1117'
}}}%%
flowchart TD
    doctor["cai doctor"]
    doctor --> sysbox["Sysbox<br/>[OK]"]
    sysbox --> ready["Ready to run!<br/>cai"]

    doctor -.->|not OK| install

    subgraph fallback["If Sysbox not available"]
        install["Install Sysbox<br/>WSL2/macOS: Run 'cai setup'<br/>Native Linux: See Sysbox docs"]
    end
```

## Step 4: Start Your First Sandbox

Navigate to a project directory (or stay in containai for testing):

```bash
# Optional: go to your project
cd /path/to/your/project

# Start the sandbox
cai
```

**Verify:**
```
Starting new sandbox container...
# or
Attaching to running container...
```

You should see the Claude agent interface (or a login prompt if not yet authenticated).

## Step 5: Authenticate Your Agent (First Run Only)

If Claude prompts you to log in, follow the authentication flow. If you need to authenticate manually:

1. Open a new terminal
2. Run `cai shell` to get a bash prompt inside the running container
3. Run `claude login` and follow the prompts

Credentials are stored in the sandbox's persistent data volume and persist across container restarts.

**Verify (from `cai shell`):**
```bash
claude --version
# Should show Claude CLI version without authentication errors
```

> **Using a different agent?** Start the sandbox with `cai --agent gemini` (on your host), then authenticate via `cai shell` and `gemini login`.

## What Just Happened?

When you ran `cai`, ContainAI:

1. **Detected isolation mode** - Checked for Sysbox runtime availability
2. **Created a named container** - Based on your git repo and branch (e.g., `myproject-main`)
3. **Mounted your workspace** - Your current directory is available at `/workspace` inside the container
4. **Created a data volume** - `sandbox-agent-data` stores your agent credentials and plugins
5. **Started the AI agent** - Claude (or your configured agent) is ready to use

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {
  'primaryColor': '#1a1a2e',
  'primaryTextColor': '#ffffff',
  'primaryBorderColor': '#16213e',
  'secondaryColor': '#0f3460',
  'tertiaryColor': '#1a1a2e',
  'lineColor': '#a0a0a0',
  'textColor': '#ffffff',
  'background': '#0d1117'
}}}%%
flowchart TB
    subgraph host["Your Host Machine"]
        subgraph runtime["Sysbox Runtime"]
            subgraph sandbox["ContainAI Sandbox"]
                workspace["/workspace<br/>Your project directory"]
                data["/mnt/agent-data<br/>Persistent credentials/plugins"]
                agent["Claude/Gemini agent running"]
            end
        end
    end
```

## Common First-Run Commands

| Command | Description |
|---------|-------------|
| `cai` | Start/attach to sandbox |
| `cai --restart` | Force recreate container (e.g., after config changes) |
| `cai doctor` | Check system capabilities |
| `cai shell` | Open bash shell in running sandbox |
| `cai stop --all` | Stop all ContainAI containers |

## Customizing Your Container

ContainAI supports user templates to customize your container environment. Templates let you install additional tools, languages, or startup scripts that persist across container recreations.

### Template Location

Templates are stored in `~/.config/containai/templates/`. The default template is installed during first use:

```
~/.config/containai/templates/
└── default/
    └── Dockerfile    # Your customizable Dockerfile
```

### Editing Your Template

Open the default template and add your customizations:

```bash
# View/edit your template
${EDITOR:-nano} ~/.config/containai/templates/default/Dockerfile
```

The template Dockerfile includes comments showing how to:
- Install system packages (apt-get)
- Add Node/Python/Rust packages
- Create startup scripts

### Using a Custom Template

```bash
# Use the default template (automatic)
cai

# Use a specific template
cai --template my-custom

# Rebuild container with template changes
cai --fresh
```

### Creating Startup Scripts

To run scripts when the container starts, create a systemd service. In Dockerfiles, you must use the symlink pattern instead of `systemctl enable` (systemd is not running during docker build):

```dockerfile
# Create your startup script
COPY my-startup.sh /opt/containai/startup/my-startup.sh
RUN chmod +x /opt/containai/startup/my-startup.sh

# Create the systemd service file
COPY my-startup.service /etc/systemd/system/my-startup.service

# Enable using symlink (NOT systemctl enable)
RUN ln -sf /etc/systemd/system/my-startup.service \
    /etc/systemd/system/multi-user.target.wants/my-startup.service
```

Example service file (`my-startup.service`):
```ini
[Unit]
Description=My Custom Startup Script
After=containai-init.service

[Service]
Type=oneshot
ExecStart=/opt/containai/startup/my-startup.sh
User=agent

[Install]
WantedBy=multi-user.target
```

### Template Warnings

When customizing templates, avoid these common mistakes:

| What NOT to do | Why |
|----------------|-----|
| Override ENTRYPOINT | systemd must be PID 1 for services to work |
| Override CMD | Required for systemd startup |
| Change USER to non-agent | Permissions will break (agent is UID 1000) |
| Use `systemctl enable` | Fails during docker build; use symlink pattern |

### Recovering a Broken Template

If your template has issues, recover it with:

```bash
# Check template status
cai doctor

# Restore default template from repo
cai doctor fix template
```

See [Configuration Reference](configuration.md#template-section) for template configuration options.

## Next Steps

- **Configure ContainAI** - See the [Technical README](../src/README.md#commands) for volume, naming, and configuration options
- **Troubleshoot issues** - See [Troubleshooting](../src/README.md#troubleshooting) for common problems
- **Customize your container** - See [Configuration Reference](configuration.md#template-section) for template options
- **Security model** - See [SECURITY.md](../SECURITY.md) for security guarantees and threat model

---

## Quick Reference

### Starting fresh each session

```bash
# Add to ~/.bashrc for permanent access
echo 'source /path/to/containai/src/containai.sh' >> ~/.bashrc

# Or source manually each session
source src/containai.sh
```

### Platform-specific notes

| Platform | Shell | Notes |
|----------|-------|-------|
| Linux | bash | Native support |
| WSL2 | bash | Native support |
| macOS | zsh default | Run `bash` first, then source |
| macOS | bash | Direct support |

### Minimum versions

- Docker Engine: 24.0+ with Sysbox runtime
- Git: any recent version
- Bash: 4.0+ (macOS default is 3.2; use `brew install bash`)

## Shell Aliases

For frequent agent usage, add aliases or functions to your shell configuration.

### Bash/Zsh (~/.bashrc or ~/.zshrc)

```bash
# Function-based aliases (recommended - cleaner argument handling)
claude() { CONTAINAI_AGENT=claude cai -- "$@"; }
gemini() { CONTAINAI_AGENT=gemini cai -- "$@"; }
codex() { CONTAINAI_AGENT=codex cai -- "$@"; }
```

### Usage

```bash
claude "Fix the bug in main.py"
gemini "Explain this code"
codex "Write tests for this function"
```

### Important: Quoting

Always quote arguments with spaces or special characters:

```bash
# Good - quoted argument passed as single string
claude "What does this function do?"

# Bad - splits into multiple arguments
claude What does this function do?
```

### Alternative: Environment Variable

If you prefer to set the agent globally for a session:

```bash
export CONTAINAI_AGENT=claude
cai -- "Fix the bug"
```

Or configure it permanently via config:

```bash
cai config set agent.default claude
```
