# For Users

**You want to run AI agents safely** - without risking your host system, without complex Docker configuration, and with your shell preferences intact.

## Start Here

1. **Install** - Clone the repo and source the CLI:
   ```bash
   git clone https://github.com/novotnyllc/containai.git
   cd containai
   source src/containai.sh
   ```

2. **Setup isolation** (one-time):
   - Linux (Ubuntu/Debian) and WSL2: Run `cai setup`
   - macOS: Run `cai setup` (uses Lima VM)
   - Other Linux distros: Follow [Setup Guide](setup-guide.md) or [Sysbox docs](https://github.com/nestybox/sysbox)

3. **Launch your first sandbox** - Navigate to your project and run `cai`:
   ```bash
   cd /path/to/project && cai
   ```

## Recommended Reading Order

1. **[Quickstart Guide](quickstart.md)** - Zero to sandbox in 5 minutes with environment verification
2. **[Container Lifecycle](lifecycle.md)** - Usage patterns: ephemeral vs persistent modes, data volumes
3. **[Configuration Reference](configuration.md)** - TOML config files, volumes, and environment variables
4. **[CLI Reference](cli-reference.md)** - Complete command documentation with examples
5. **[Troubleshooting](troubleshooting.md)** - Common issues and fixes for Docker, SSH, and agents

## Reading Path

```mermaid
%%{init: {'theme': 'base'}}%%
flowchart TD
    accTitle: User documentation navigation
    accDescr: Flowchart showing the recommended reading path for ContainAI users, starting from quickstart through configuration to troubleshooting.

    START["Start Here"]
    QS["Quickstart Guide"]
    CFG["Configuration"]
    LC["Lifecycle"]
    CLI["CLI Reference"]
    TS["Troubleshooting"]

    START --> QS
    QS --> LC
    LC --> CFG
    CFG --> CLI
    CLI -.->|"When issues arise"| TS
    QS -.->|"Quick help"| TS

    subgraph core["Core Concepts"]
        LC
        CFG
    end

    subgraph reference["Reference Material"]
        CLI
        TS
    end
```

## Key Features for Users

### Preferences Sync

Your git config, shell aliases, and editor settings carry into the container automatically. The environment feels like your local machine, not a sterile sandbox.

- See [Configuration > Sync Section](configuration.md) for what gets synced
- Use `cai import` to manually refresh synced files

### Ephemeral or Persistent

Choose your workflow:

| Mode | Command | Use Case |
|------|---------|----------|
| Persistent | `cai` | Long-lived dev environment with saved state |
| Fresh volume | `cai --reset` | Starts fresh with new volume (old preserved) |
| Force recreate | `cai --restart` | Recreate container, keep data volume |

See [Lifecycle](lifecycle.md) for details on container and volume management.

### Multiple Agents

ContainAI supports different AI agents:

```bash
cai                           # Default agent (claude)
CONTAINAI_AGENT=gemini cai    # Use Gemini instead
```

Set the default agent in your config with `[agent].default = "gemini"`.

### SSH Access

Connect via VS Code Remote-SSH or standard SSH. First configure SSH access:

```bash
cai shell   # Configures SSH for your container
ssh <container-name>  # Connect using container name
```

See [Troubleshooting](troubleshooting.md#ssh-connection-issues) for port configuration (dynamic range 2300-2500).

## Quick Reference

| Command | Description |
|---------|-------------|
| `cai` | Start or attach to sandbox |
| `cai doctor` | Check system capabilities |
| `cai shell` | Open bash shell in running sandbox |
| `cai import` | Sync host dotfiles to container |
| `cai stop --all` | Stop all ContainAI containers |
| `cai --help` | Full command reference |

## Other Perspectives

- **[For Contributors](for-contributors.md)** - Want to improve ContainAI? Start here
- **[For Security Auditors](for-security-auditors.md)** - Evaluating ContainAI's security posture
