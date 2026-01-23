# Configuration Reference

Complete reference for ContainAI's TOML configuration system.

## Config File Locations

ContainAI searches for configuration in this order:

| Location | Scope | Example |
|----------|-------|---------|
| `.containai/config.toml` | Workspace (checked in with repo) | `/project/.containai/config.toml` |
| `~/.config/containai/config.toml` | User (XDG default) | `/home/user/.config/containai/config.toml` |

**Discovery behavior:**

1. Starting from the workspace directory, walk up the directory tree
2. At each directory, check for `.containai/config.toml`
3. **Stop at git root** - if in a git repo, config search does not traverse above the repository boundary
4. If not in a git repo, discovery walks up to filesystem root (but never checks `/.containai/config.toml`)
5. If no workspace config found, check user config at `XDG_CONFIG_HOME/containai/config.toml`
6. If `XDG_CONFIG_HOME` is not set, defaults to `~/.config`

```
/home/user/projects/myapp/src/  <- workspace (cwd)
/home/user/projects/myapp/.containai/config.toml  <- found first (wins)
/home/user/projects/myapp/.git  <- git root (stops search)
/home/user/.config/containai/config.toml  <- fallback (not checked if above found)
```

**Note:** Root filesystem config (`/.containai/config.toml`) is never checked for security reasons.

## Precedence

Configuration values are resolved with this precedence (highest to lowest):

1. **CLI flags** - `--data-volume`, `--agent`, `--credentials`, `--config`
2. **Environment variables** - `CONTAINAI_DATA_VOLUME`, `CONTAINAI_AGENT`, etc.
3. **Workspace config section** - `[workspace."<path>"]` matching current workspace
4. **Global config section** - `[agent]`, `[credentials]`, etc.
5. **Built-in defaults** - `sandbox-agent-data`, `claude`, `none`

When a CLI flag or environment variable is provided, config file parsing is **skipped entirely** for that value.

## Schema Reference

### `[agent]` Section

Global agent configuration.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `default` | string | `"claude"` | Default agent to use (`claude`, `gemini`, etc.) |
| `data_volume` | string | `"sandbox-agent-data"` | Docker volume for agent data and credentials |

```toml
[agent]
default = "claude"
data_volume = "sandbox-agent-data"
```

**Volume name rules:**
- 1-255 characters
- Must start with alphanumeric (`a-z`, `A-Z`, `0-9`)
- May contain alphanumeric, underscore (`_`), dot (`.`), or dash (`-`)
- Invalid names cause an error

### `[credentials]` Section

Credential handling configuration.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mode` | string | `"none"` | Credential mode: `none` (safe) |

```toml
[credentials]
mode = "none"
```

**Security restriction:** Setting `credentials.mode = "host"` in config is **ignored**. Host credentials require explicit CLI opt-in via `--allow-host-credentials` (or legacy `--credentials=host`). This prevents config files from escalating privileges without user awareness.

### `[secure_engine]` Section

Secure container engine configuration (Sysbox/ECI).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `context_name` | string | `""` | Docker context name for secure engine |

```toml
[secure_engine]
context_name = "desktop-linux"
```

**Context name rules:**
- Max 64 characters
- Alphanumeric, underscore (`_`), or dash (`-`) only
- No control characters (newlines, tabs)
- Empty string means use default context

**Environment override:** `CONTAINAI_SECURE_ENGINE_CONTEXT`

### `[ssh]` Section

SSH connection configuration for containers. Controls port allocation, agent forwarding, and port tunneling.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `port_range_start` | integer | `2300` | Start of SSH port range for container allocation |
| `port_range_end` | integer | `2500` | End of SSH port range for container allocation |
| `forward_agent` | boolean | `false` | Enable SSH agent forwarding to container |
| `local_forward` | array of strings | `[]` | Local port forwarding entries |

```toml
[ssh]
port_range_start = 2300
port_range_end = 2500
forward_agent = true
local_forward = ["8080:localhost:8080", "3000:localhost:3000"]
```

**Port range rules:**
- Values must be between 1024 and 65535
- Range should be large enough for concurrent containers
- Ports are allocated dynamically on container start

**Forward agent:**
- When `true`, adds `ForwardAgent yes` to SSH config
- Allows the container to use your local SSH agent for authentication
- **SECURITY WARNING:** An attacker with root access on the container could hijack the forwarded agent to authenticate to other hosts. Only enable if you trust the container environment.

**Local forward format:**
- Each entry: `"localport:remotehost:remoteport"`
- Example: `"8080:localhost:8080"` forwards local port 8080 to container's localhost:8080
- Useful for accessing web servers or databases running in the container
- Invalid entries are skipped with a warning

**VS Code Remote-SSH compatibility:**
- The generated SSH config is fully compatible with VS Code Remote-SSH extension
- Use the container name as the SSH host in VS Code (run `cai list` to see container names)
- Container names are automatically generated based on workspace path hash
- Port forwarding configured here will be available in VS Code sessions

### `[env]` Section

Environment variable import configuration. This section is **global-only** (no workspace overrides).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `import` | array of strings | `[]` | Environment variable names to import (explicit names only, no wildcards) |
| `from_host` | boolean | `false` | Import from host environment |
| `env_file` | string | `null` | Workspace-relative path to `.env` file to load |

```toml
[env]
import = ["GITHUB_TOKEN", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"]
from_host = true
env_file = ".env.local"
```

**Import list rules:**
- Each entry must be a valid POSIX environment variable name
- Pattern: `^[A-Za-z_][A-Za-z0-9_]*$`
- **No wildcards** - each variable must be listed explicitly
- Invalid names are skipped with a warning

**env_file rules:**
- Must be workspace-relative (no absolute paths)
- Cannot escape workspace directory (e.g., `../secrets.env` is rejected)
- Symlinks are rejected for security
- File must exist and be readable

**Behavior:**
- If `[env]` section is missing, no environment variables are imported (silent)
- If `import` is missing or invalid, treated as empty list with a warning

### `[danger]` Section

Optional audit trail for dangerous features. **This section is informational only - CLI flags are the actual gates.**

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `allow_host_credentials` | boolean | `false` | Audit marker for host credential access |
| `allow_host_docker_socket` | boolean | `false` | Audit marker for Docker socket access |

```toml
[danger]
allow_host_credentials = true
allow_host_docker_socket = true
```

**Important:** The `[danger]` section does **not** enable dangerous features. CLI flags are the only gates:

| Feature | CLI Flag Required |
|---------|-------------------|
| Host credentials | `--allow-host-credentials` |
| Docker socket | `--allow-host-docker-socket` |

The `[danger]` config keys do not enable or bypass safety gates - CLI flags are still required. These keys are parsed and available for audit purposes but currently have no effect on runtime behavior. See `cai --help` for CLI flag details.

### `default_excludes` (Top-level)

Global list of patterns to exclude from import and export operations.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `default_excludes` | array of strings | `[]` | Patterns excluded from import/export operations |

```toml
default_excludes = [
    "claude/skills",
    "vscode-server/extensions",
    "*.log"
]
```

**What these patterns affect:**

- **`cai import`** - Patterns are passed to `rsync --exclude` when syncing host configs to the data volume. Patterns are relative to each sync source root.
- **`cai export`** - Patterns are passed to `tar --exclude` when archiving the data volume. Patterns are relative to the volume root (`/mnt/agent-data`).

**Pattern syntax:**

- Patterns are passed through to rsync/tar; semantics depend on the underlying tool
- Patterns without `/` match any path component: `skills` matches at any depth
- Glob patterns (`*`, `?`) are supported
- No multi-line values allowed (dropped silently for security)
- Patterns from `default_excludes` and workspace-specific `excludes` are merged (deduplicated)

**Examples:**
```toml
default_excludes = [
    "claude/skills",           # Exclude Claude skills directory
    "vscode-server/extensions", # Exclude VS Code extensions
    "*.log",                   # Exclude all log files
]
```

See rsync(1) and tar(1) documentation for detailed pattern matching rules.

### `[workspace."<path>"]` Sections

Workspace-specific configuration overrides.

| Key | Type | Description |
|-----|------|-------------|
| `data_volume` | string | Override volume for this workspace |
| `excludes` | array of strings | Additional exclude patterns for import/export (merged with `default_excludes`) |

```toml
[workspace."/home/user/projects/frontend"]
data_volume = "frontend-agent-data"
excludes = ["claude/skills", "*.tmp"]

[workspace."/home/user/projects/backend"]
data_volume = "backend-agent-data"
excludes = ["codex/skills"]
```

**Workspace matching:**
- Paths must be **absolute**
- Matching uses **longest path prefix** (most specific wins)
- Relative paths in config are ignored

**Example matching:**
```
Workspace cwd: /home/user/projects/frontend/src/components

Config sections:
  [workspace."/home/user/projects"]           <- matches (2 segments)
  [workspace."/home/user/projects/frontend"]  <- matches (3 segments, wins!)
  [workspace."/home/user/other"]              <- no match
```

## Example Configurations

### Single Workspace (Simple)

Minimal config for a single project:

```toml
# .containai/config.toml

[agent]
default = "claude"
data_volume = "myproject-agent-data"

default_excludes = [
    "*.log",
    "*.tmp"
]
```

### Multi-Workspace

User config managing multiple projects:

```toml
# ~/.config/containai/config.toml

[agent]
default = "claude"
data_volume = "shared-agent-data"

default_excludes = [
    "*.log",
    "*.tmp"
]

[workspace."/home/user/work/project-a"]
data_volume = "project-a-data"
excludes = ["claude/skills"]

[workspace."/home/user/work/project-b"]
data_volume = "project-b-data"
excludes = ["codex/skills"]

[workspace."/home/user/personal"]
data_volume = "personal-data"
```

### Multi-Agent

Configuration for teams using different AI agents:

```toml
# ~/.config/containai/config.toml

[agent]
default = "claude"
data_volume = "default-agent-data"

[workspace."/home/user/gemini-projects"]
data_volume = "gemini-agent-data"
# Note: agent selection is global via [agent].default or CLI --agent flag
# Per-workspace agent selection is not supported

[workspace."/home/user/claude-projects"]
data_volume = "claude-agent-data"

[env]
import = ["ANTHROPIC_API_KEY", "GOOGLE_API_KEY"]
from_host = true
```

### Advanced: Environment Import

Configuration with environment variable import:

```toml
# .containai/config.toml

[agent]
default = "claude"

[env]
# Each variable must be listed explicitly (no wildcards)
import = [
    "GITHUB_TOKEN",
    "NPM_TOKEN",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_REGION",
    "AWS_DEFAULT_REGION"
]
from_host = true
env_file = ".env.sandbox"  # Workspace-relative path

default_excludes = [
    "*.log",
    "*.tmp"
]
```

### Advanced: Secure Engine Override

For environments with custom Docker contexts:

```toml
# ~/.config/containai/config.toml

[agent]
default = "claude"

[secure_engine]
context_name = "secure-linux"
```

## Environment Variables

These environment variables override config file values:

| Variable | Overrides | Example |
|----------|-----------|---------|
| `CONTAINAI_DATA_VOLUME` | `agent.data_volume` | `CONTAINAI_DATA_VOLUME=custom-vol` |
| `CONTAINAI_AGENT` | `agent.default` | `CONTAINAI_AGENT=gemini` |
| `CONTAINAI_CREDENTIALS` | `credentials.mode` | `CONTAINAI_CREDENTIALS=none` |
| `CONTAINAI_SECURE_ENGINE_CONTEXT` | `secure_engine.context_name` | `CONTAINAI_SECURE_ENGINE_CONTEXT=desktop-linux` |

## Error Handling

### Discovered vs Explicit Config

| Scenario | Discovered Config | Explicit Config (`--config`) |
|----------|-------------------|------------------------------|
| File not found | Silent (use defaults) | **Error** |
| Parse error (invalid TOML) | Warning (use defaults) | **Error** |
| Python unavailable | Warning (use defaults) | **Error** |
| Invalid volume name | **Error** | **Error** |
| Invalid context name | Warning (ignored) | Warning (ignored) |
| Multiline exclude pattern | Dropped silently | Dropped silently |

**Note:** Invalid volume names (`agent.data_volume`, `workspace.*.data_volume`) always cause errors regardless of config source, as the container cannot start with an invalid volume.

### Common Errors

```
[ERROR] Config file not found: /path/to/config.toml
```
Explicit `--config` path does not exist.

```
[ERROR] Invalid volume name: my:bad:volume
```
Volume name contains invalid characters.

```
[WARN] Failed to parse config file: /path/to/config.toml
```
TOML syntax error in discovered config (using defaults).

```
[WARN] Python not found, cannot parse config. Using defaults.
```
Python 3 with TOML support not available.

## Implementation Details

Configuration is implemented in:
- [`lib/config.sh`](../src/lib/config.sh) - Bash config resolution
- [`parse-toml.py`](../src/parse-toml.py) - TOML parsing (requires Python 3.11+ or `tomli`/`toml` package)

Key functions:
- `_containai_find_config()` - Discovery with git boundary
- `_containai_parse_config()` - Parse with workspace matching
- `_containai_resolve_volume()` - Volume resolution with precedence
- `_containai_resolve_agent()` - Agent resolution
- `_containai_resolve_credentials()` - Credentials with security block
- `_containai_resolve_env_config()` - Environment variable config

## See Also

- [Quickstart Guide](quickstart.md) - Getting started with ContainAI
- [Technical README](../src/README.md) - Full CLI documentation
- [SECURITY.md](../SECURITY.md) - Security model and guarantees
