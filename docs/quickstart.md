# Quickstart Guide

Get from zero to your first AI sandbox in under 5 minutes.

## Prerequisites

Before starting, ensure you have:

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| Docker CLI | Any recent | `docker --version` |
| Bash shell | 4.0+ | `echo "${BASH_VERSION}"` |
| Git | Any | `git --version` |

> **Shell note:** ContainAI requires **bash 4.0+**. If you use zsh, fish, or another shell, run `bash` first. macOS ships with bash 3.2; install a newer version via Homebrew (`brew install bash`).
> **Runtime note:** `cai setup` provisions the isolation runtime (Linux/WSL2 installs a ContainAI-managed Docker daemon bundle and Sysbox on supported distros; macOS configures Lima).

## Step 1: Clone the Repository

```bash
git clone https://github.com/novotnyllc/containai.git
cd containai
```

## Step 2: Install the CLI

```bash
./install.sh --yes --no-setup
```

`install.sh` bootstraps the `cai` binary and delegates installation to:

```bash
cai install --yes --no-setup
```

**Verify:**
```bash
cai --help | head -3
# Should show:
# ContainAI native CLI
# ...
```

> **Note:** `cai install` writes `cai` into `~/.local/share/containai` and installs wrappers in `~/.local/bin` by default.

## CLI Output Behavior

ContainAI follows the Unix Rule of Silence: commands produce no output on success by default.

| Output Type | Default | `--verbose` |
|-------------|---------|-------------|
| Info/step messages | Hidden | Shown |
| Warnings | Shown (stderr) | Shown |
| Errors | Shown (stderr) | Shown |

**Enable verbose output:**
```bash
# Per-command flag
cai --verbose doctor

# Environment variable (persistent)
export CONTAINAI_VERBOSE=1
```

**Precedence**: `--verbose` flag > `CONTAINAI_VERBOSE` environment variable.

**Exceptions**: `cai doctor`, `cai help`, and `cai version` always produce output regardless of verbosity settings.

## Step 3: Check Your Environment

Run the doctor command to detect your system's capabilities:

```bash
cai doctor
```

**What to look for:**

| Output | Meaning | Action |
|--------|---------|--------|
| `Sysbox: [OK]` | Sysbox runtime configured | Ready to go! |
| `Sysbox: [ERROR]` | No isolation available | Run `cai setup` (see below) |

### Runtime Decision Tree

```mermaid
flowchart TD
    doctor["cai doctor"]
    doctor --> sysbox["Sysbox<br/>[OK]"]
    sysbox --> ready["Ready to run!<br/>cai"]

    doctor -.->|not OK| install

    subgraph fallback["If Sysbox not available"]
        install["Run 'cai setup'<br/>Linux (Ubuntu/Debian), WSL2, macOS<br/>Other Linux: see Setup Guide for manual Sysbox"]
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
4. **Created a data volume** - `containai-data` stores your agent credentials and plugins
5. **Started the AI agent** - Claude (or your configured agent) is ready to use

```mermaid
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

For quick customizations that don't require rebuilding images, see:
- **[Startup Hooks](configuration.md#startup-hooks-runtime-mounts)** - Run scripts at container start
- **[Network Policies](configuration.md#network-policy-files-runtime-mounts)** - Control egress traffic

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

- **Container lifecycle** - See [Container Lifecycle](lifecycle.md) for details on creation, stopping, and garbage collection
- **Configure ContainAI** - See the [Technical README](../src/README.md#commands) for volume, naming, and configuration options
- **Troubleshoot issues** - See [Troubleshooting](../src/README.md#troubleshooting) for common problems
- **Customize your container** - See [Configuration Reference](configuration.md#template-section) for template options
- **Security model** - See [SECURITY.md](../SECURITY.md) for security guarantees and threat model

---

## Quick Reference

### Starting fresh each session

```bash
# Add to ~/.bashrc for permanent access
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Or in current shell session
export PATH="$HOME/.local/bin:$PATH"
```

### Platform-specific notes

| Platform | Shell | Notes |
|----------|-------|-------|
| Linux | bash | Native support |
| WSL2 | bash | Native support |
| macOS | zsh default | Run `bash` first if needed |
| macOS | bash | Direct support |

### Minimum versions

- Docker CLI: any recent version
- Isolation runtime: run `cai setup` (Linux/WSL2/macOS); for other Linux distros, follow the [Setup Guide](setup-guide.md)
- Git: any recent version
- Bash: 4.0+ (macOS default is 3.2; use `brew install bash`)

## Shell Functions

For frequent agent usage, add wrapper functions to your `~/.bashrc`:

```bash
# Agent wrapper functions (add to ~/.bashrc)
claude() { CONTAINAI_AGENT=claude cai -- "$@"; }
gemini() { CONTAINAI_AGENT=gemini cai -- "$@"; }
```

> **Note:** ContainAI requires bash 4.0+, so these functions belong in `~/.bashrc`, not `~/.zshrc`. If you use zsh as your default shell, run `bash` first (as noted in the prerequisites), then these functions will be available.

### Usage

```bash
claude "Fix the bug in main.py"
gemini "Explain this code"
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

Set the agent for the current session:

```bash
export CONTAINAI_AGENT=claude
cai -- "Fix the bug"
```

Or configure it permanently:

```bash
cai config set agent.default claude
```
