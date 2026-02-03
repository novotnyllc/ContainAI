# ContainAI Setup and Diagnostics

Use this skill when: setting up ContainAI, diagnosing issues, checking system requirements, validating configuration.

## Doctor Command

Check system capabilities and diagnostics.

```bash
cai doctor [options]
```

### Options

```bash
--json                # Machine-parseable JSON output
--build-templates     # Run heavy template validation (actual docker build)
--reset-lima          # (macOS only) Delete Lima VM and Docker context
```

### What It Checks

1. **Docker availability** - Docker CLI and daemon accessible
2. **Sysbox runtime** - Required for secure isolation
3. **Context configuration** - Docker context for ContainAI
4. **SSH configuration** - SSH client available, config directory exists
5. **Template validity** - Template Dockerfiles parse correctly
6. **Resource limits** - Available memory and CPU

### Output

```bash
$ cai doctor

ContainAI Doctor
────────────────────────────
[OK] Docker available (Docker version 24.0.5)
[OK] Sysbox runtime detected
[OK] Context 'containai-docker' configured
[OK] SSH configuration valid
[OK] Default template valid

All checks passed. ContainAI is ready to use.
```

### JSON Output

```bash
cai doctor --json
```

Returns structured JSON for scripting:

```json
{
  "docker": {"status": "ok", "version": "24.0.5"},
  "sysbox": {"status": "ok"},
  "context": {"status": "ok", "name": "containai-docker"},
  "ssh": {"status": "ok"},
  "template": {"status": "ok", "name": "default"}
}
```

### Doctor Fix

Attempt automatic fixes for common issues.

```bash
cai doctor fix [target]
```

Targets:
- `volume [--all|<name>]` - Fix volume permissions
- `container [--all|<name>]` - Fix container issues
- `template [--all|<name>]` - Rebuild templates

```bash
cai doctor fix volume --all     # Fix all volumes
cai doctor fix container foo    # Fix specific container
cai doctor fix template default # Rebuild default template
```

## Setup Command

Configure secure container isolation.

```bash
cai setup [options]
```

### Platform-Specific Setup

**Linux/WSL2:**
- Installs Sysbox runtime
- Configures Docker context
- Sets up systemd integration

**macOS:**
- Configures Lima VM with Sysbox
- Sets up Docker context
- Manages VM lifecycle

### Options

```bash
--force               # Force reinstall even if already configured
--verbose             # Show detailed progress
```

### Examples

```bash
cai setup             # Interactive setup
cai setup --force     # Force reconfiguration
```

## Validate Command

Validate Secure Engine configuration.

```bash
cai validate [options]
```

Checks:
- Sysbox runtime is functional
- Docker context is correctly configured
- Container isolation is working

### Examples

```bash
cai validate          # Run validation
cai validate --verbose # Detailed output
```

## Config Command

Manage ContainAI settings.

```bash
cai config <subcommand> [options]
```

### Subcommands

```bash
cai config list                    # Show all settings with source
cai config get <key>               # Get effective value
cai config set <key> <value>       # Set value
cai config unset <key>             # Remove setting
```

### Scoping Options

```bash
-g, --global          # Force global scope
--workspace <path>    # Apply to specific workspace
```

### Available Keys

**Workspace-scoped:**
- `data_volume` - Data volume name for workspace

**Global:**
- `agent.default` - Default agent (alias: `agent`)
- `ssh.forward_agent` - Enable SSH agent forwarding
- `ssh.port_range_start` - SSH port range start
- `ssh.port_range_end` - SSH port range end
- `import.auto_prompt` - Prompt for import on new volume

### Source Values

| Source | Meaning |
|--------|---------|
| cli | Command-line flag |
| env | Environment variable |
| workspace:<path> | Workspace state |
| repo-local | `.containai/config.toml` |
| user-global | `~/.config/containai/config.toml` |
| default | Built-in default |

### Examples

```bash
cai config list                        # Show all settings
cai config get agent                   # Get default agent
cai config set agent.default claude    # Set global default
cai config set data_volume my-vol      # Set workspace volume
cai config unset data_volume           # Remove workspace setting
cai config unset -g ssh.forward_agent  # Remove global setting
```

## Version and Update

### Check Version

```bash
cai version           # Show current version
```

### Update ContainAI

```bash
cai update            # Update to latest version
```

## Common Setup Patterns

### First-Time Setup

```bash
# 1. Run setup
cai setup

# 2. Verify everything works
cai doctor

# 3. Test with a simple container
cai run --dry-run
cai shell
```

### Troubleshoot Failing Setup

```bash
# 1. Check what's wrong
cai doctor

# 2. Follow remediation steps in output

# 3. Re-run setup if needed
cai setup --force

# 4. Verify fix
cai doctor
```

### Verify After System Update

```bash
# After Docker or OS updates
cai doctor
cai validate
```

### Reset Everything

```bash
# Stop all containers
cai stop --all --remove

# Run setup fresh
cai setup --force

# Verify
cai doctor
```

## Configuration Files

### User Global Config

Location: `~/.config/containai/config.toml`

```toml
[agent]
default = "claude"

[ssh]
forward_agent = true
port_range_start = 2222
port_range_end = 2322

[import]
auto_prompt = true
```

### Repository Config

Location: `.containai/config.toml` (in project root)

```toml
[container]
memory = "8g"
cpus = 4

[import]
additional_paths = ["~/.npmrc"]
```

### Workspace State

Location: `~/.local/state/containai/workspaces/<hash>/state.toml`

Managed by ContainAI, contains:
- Data volume name
- Container preferences

## Gotchas

### Sysbox Required

ContainAI requires Sysbox runtime. Without it, `cai run` will fail. Run `cai doctor` to check.

### Docker Context

ContainAI uses a dedicated Docker context (`containai-docker` by default). This ensures isolation from your regular Docker usage. Use `cai docker` to run Docker commands in the ContainAI context.

### Permission Issues

If you see permission errors:
```bash
cai doctor fix volume --all
```

### Lima VM (macOS)

On macOS, ContainAI uses a Lima VM. If it becomes corrupted:
```bash
cai doctor --reset-lima
cai setup
```

### Port Range

Default SSH port range is 2222-2322 (100 containers max). Increase if needed:
```bash
cai config set ssh.port_range_end 2422
```

## Related Skills

- `containai-quickstart` - Getting started
- `containai-troubleshooting` - Error resolution
- `containai-customization` - Advanced configuration
