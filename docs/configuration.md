# Configuration Reference

This document provides a comprehensive reference for all configuration options in ContainAI, including environment variables, host configuration files, and agent configuration.

## Environment Variables

These variables control the behavior of the host launcher scripts and the runtime environment.

### Installation & Paths

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINAI_INSTALL_ROOT` | `/opt/containai` | The root directory where the ContainAI payload is installed. |
| `CONTAINAI_LOCAL_REMOTES_DIR` | `~/.containai/local-remotes` | Directory where bare git repositories are stored for local synchronization. |
| `CONTAINAI_AUDIT_LOG` | `~/.config/containai/security-events.log` | Path to the security audit log file. |

### Runtime Behavior

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINAI_DISABLE_AUTO_SYNC` | `0` | Set to `1` to disable the automatic fast-forward of the host working tree after a container push. |
| `LAUNCHER_UPDATE_POLICY` | `prompt` | Controls launcher update checks: `prompt`, `always`, or `never`. |
| `CONTAINER_RUNTIME` | `docker` | The container runtime executable to use (e.g., `podman` - experimental). |
| `DOCKER_BUILDKIT` | `1` | Enable Docker BuildKit for faster builds. |
| `TZ` | (Auto-detected) | Timezone to set inside the container (e.g., `America/New_York`). |

### Security & Isolation

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINAI_DIRTY_OVERRIDE_TOKEN` | None | Token to allow launching with modified host scripts (bypasses integrity check). |
| `CONTAINAI_HELPER_NETWORK_POLICY` | `none` | Network mode for helper containers (broker/proxy): `none`, `loopback`, `host`, `bridge`. |
| `CONTAINAI_HELPER_PIDS_LIMIT` | `64` | Process ID limit for helper containers. |
| `CONTAINAI_HELPER_MEMORY` | `512m` | Memory limit for helper containers. |

### Output Variables (Read-Only)

These variables are exported by the launcher for downstream tools or logging.

| Variable | Description |
|----------|-------------|
| `CONTAINAI_SESSION_CONFIG_SHA256` | SHA256 hash of the rendered session configuration manifest. |

## Configuration Files

### Host Configuration (`host-config.env`)

**Location:**
- Linux/macOS: `~/.config/containai/host-config.env`
- Windows: `%USERPROFILE%\.config\containai\host-config.env`

**Format:** Key-value pairs (shell/env format).

**Example:**
```bash
LAUNCHER_UPDATE_POLICY=always
CONTAINAI_DISABLE_AUTO_SYNC=1
```

### MCP Secrets (`mcp-secrets.env`)

**Location:** `~/.config/containai/mcp-secrets.env`

**Format:** Key-value pairs. Used to inject API keys into the Secret Broker.

**Example:**
```bash
GITHUB_TOKEN=ghp_...
CONTEXT7_API_KEY=...
```

### Agent Configuration (`config.toml`)

**Location:** Repository root (`config.toml`) or `agent-configs/<agent>/config.toml`.

**Format:** TOML. Defines MCP servers and agent-specific settings.

**Structure:**

```toml
[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp"
bearer_token_env_var = "GITHUB_TOKEN"

[mcp_servers.custom]
command = "npx"
args = ["-y", "@my-org/mcp-server"]
env = { "API_KEY" = "${MY_API_KEY}" }
```

## Network Proxy Modes

Passed via `--network-proxy` flag or `NETWORK_PROXY` environment variable.

| Mode | Description |
|------|-------------|
| `allow-all` | (Default) Full outbound network access. |
| `restricted` | No network access (`--network none`). |
| `squid` | Forces traffic through the Squid sidecar proxy. |

## Resource Limits

Passed via flags (`--cpu`, `--memory`) or environment variables.

| Flag | Env Var | Default |
|------|---------|---------|
| `--cpu` | `CONTAINAI_CPU_LIMIT` | `4` |
| `--memory` | `CONTAINAI_MEMORY_LIMIT` | `8g` |
| `--gpu` | `CONTAINAI_GPU_SPEC` | None |
