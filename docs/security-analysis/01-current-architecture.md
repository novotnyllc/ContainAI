# Current Architecture: Detailed Analysis

## Purpose

This document provides a comprehensive, code-based analysis of the current CodingAgents architecture, with focus on security-relevant design decisions.

## Container Architecture

### Base Image (coding-agents-base:local)

**File:** `docker/base/Dockerfile`

**User Configuration:**
```dockerfile
# Line 199-203
useradd -m -s /bin/bash -u 1000 agentuser
mkdir -p /workspace /home/agentuser/.config /home/agentuser/.local/share
chown -R agentuser:agentuser /workspace /home/agentuser
USER agentuser
WORKDIR /home/agentuser
```

**Analysis:**
- ✅ Non-root user (UID 1000) - matches most host systems
- ✅ Dedicated workspace directory
- ✅ Consistent user context for all operations
- ⚠️ No explicit capability restrictions in Dockerfile

### Container Launch (launch-agent)

**File:** `scripts/launchers/launch-agent` (bash), `scripts/launchers/launch-agent.ps1` (PowerShell)

**Security Options Applied:**

**Bash (line 615):**
```bash
DOCKER_ARGS+=(
    "-w" "/workspace"
    "--network" "$NETWORK_MODE"
    "--security-opt" "no-new-privileges:true"
    "--cpus=$CPU"
    "--memory=$MEMORY"
)
```

**PowerShell (lines 606-611):**
```powershell
$dockerArgs += "-w", "/workspace"
$dockerArgs += "--network", $NetworkMode
$dockerArgs += "--cap-drop=ALL"  # ← ONLY IN POWERSHELL
$dockerArgs += "--security-opt", "no-new-privileges:true"
$dockerArgs += "--pids-limit=4096"
```

**Critical Finding:** 
- ❌ **Capability drop missing in bash launcher** - PowerShell has `--cap-drop=ALL`, bash does not
- This is an **inconsistency** that should be fixed

**Analysis:**
- ✅ `no-new-privileges:true` prevents setuid/setgid escalation
- ✅ Resource limits (CPU, memory) prevent DoS
- ✅ PowerShell: All Linux capabilities dropped
- ❌ Bash: Linux capabilities NOT dropped (inconsistent)
- ⚠️ No seccomp profile
- ⚠️ No AppArmor profile
- ⚠️ No read-only root filesystem

### No Docker Socket Access

**Verified:** Grep through all launcher scripts shows NO docker.sock mounts:

```bash
# Confirmed: No lines containing docker.sock or /var/run/docker.sock
grep -r "docker.sock" scripts/launchers/
# Returns: (empty)
```

**Analysis:**
- ✅ Docker socket is **never** mounted
- ✅ Container cannot control host Docker daemon
- ✅ Container escape via Docker API is structurally impossible

## Filesystem Isolation

### Workspace Model

**File:** `scripts/launchers/launch-agent` lines 456-492

**Key Mount Points:**

```bash
# Source repository (read-only)
"-v" "${WSL_PATH}:/tmp/source-repo:ro"

# Workspace is COPIED inside container, not bind-mounted
# See entrypoint.sh lines 158-162 (copy operation)
```

**Workspace Setup (entrypoint.sh):**
```bash
# Copy source repo to workspace (line 158-162)
if [ -d /tmp/source-repo ]; then
    echo "Copying source repository to workspace..."
    cp -a /tmp/source-repo/. /workspace/
    rm -rf /tmp/source-repo
fi
```

**Analysis:**
- ✅ **Critical:** Workspace is COPIED, not bind-mounted
- ✅ True filesystem isolation - no shared state with host
- ✅ Container cannot modify host repository directly
- ✅ Changes confined to container until explicitly pushed
- ✅ Host repository remains intact even if container is compromised

### Authentication Mounts (Read-Only)

**File:** `scripts/launchers/launch-agent` lines 474-516

```bash
# All authentication configs are read-only
"-v" "${HOME}/.gitconfig:/home/agentuser/.gitconfig:ro"
"-v" "${HOME}/.config/gh:/home/agentuser/.config/gh:ro"
"-v" "${HOME}/.config/github-copilot:/home/agentuser/.config/github-copilot:ro"
"-v" "${HOME}/.config/codex:/home/agentuser/.config/codex:ro"
"-v" "${HOME}/.config/claude:/home/agentuser/.config/claude:ro"
"-v" "${HOME}/.config/coding-agents/mcp-secrets.env:/home/agentuser/.mcp-secrets.env:ro"
"-v" "${HOME}/.git-credentials:/home/agentuser/.git-credentials:ro"
```

**Analysis:**
- ✅ All auth configs mounted with `:ro` flag
- ✅ Container cannot modify host credentials
- ✅ Credential exfiltration possible (by design), but not modification
- ✅ Revoke on host = immediately revoked in container

### What's NOT Mounted

**Verified by code inspection:**

NOT mounted:
- ❌ `/` or any host system directories
- ❌ `~` or user home directory (except specific config dirs)
- ❌ `/var/run/docker.sock`
- ❌ `/dev` devices (except standard container devices)
- ❌ Host `/tmp` or other writable directories
- ❌ Other project directories

**Analysis:**
- ✅ Minimal attack surface
- ✅ Host system files unreachable from container
- ✅ No path traversal to host filesystem

## Credential & Secret Management

### Git Credential Proxy

**Files:** 
- `scripts/runtime/git-credential-proxy-server.sh` (host-side)
- `scripts/runtime/git-credential-host-helper.sh` (container-side)

**Launch Integration (lines 517-582):**
```bash
# Start proxy server on host
CREDENTIAL_SOCKET_PATH="${HOME}/.config/coding-agents/git-credential.sock"
nohup "$CREDENTIAL_PROXY_SCRIPT" "$CREDENTIAL_SOCKET_PATH" > /dev/null 2>&1 &

# Mount socket into container (read-only)
"-v" "$CREDENTIAL_SOCKET_PATH:/tmp/git-credential-proxy.sock:ro"
"-e" "CREDENTIAL_SOCKET=/tmp/git-credential-proxy.sock"
```

**Architecture:**
```
Container                     Host
────────────────────────────────────────────
git command                   git credential helpers
    ↓                              ↑
helper script  →  socket  →  proxy server
(read-only)       (ro)         (manages creds)
```

**Analysis:**
- ✅ Credentials never stored in container filesystem
- ✅ Socket mounted read-only
- ✅ Proxy mediates access to host credential helpers
- ✅ Container cannot modify credential store
- ⚠️ Credentials are accessible (by design for functionality)

### GPG Signing Proxy

Similar architecture for commit signing:
- GPG private keys stay on host
- Socket-based proxy for signing operations
- Container can request signatures but never sees private keys

### MCP Secrets

**File:** Mounted from `~/.config/coding-agents/mcp-secrets.env`

**Mount:** Read-only
**Purpose:** API keys for MCP servers (GitHub, Context7, etc.)

**Analysis:**
- ✅ Secrets outside git repository
- ✅ Read-only mount
- ⚠️ Secrets are accessible to container (required for MCP functionality)

## Network Configuration

### Three Network Modes

**File:** `scripts/launchers/launch-agent` lines 143-153

**1. allow-all (default):**
```bash
NETWORK_MODE="bridge"  # Standard Docker networking
```
- Full internet access
- Can reach any external service
- Standard for development

**2. restricted:**
```bash
NETWORK_MODE="none"  # No networking
```
- Cannot reach any network
- Cannot clone from URLs
- Maximum isolation

**3. squid:**
```bash
NETWORK_MODE="$PROXY_NETWORK_NAME"  # Custom network with proxy
```
- HTTP/HTTPS routed through Squid proxy
- Domain allowlist enforced
- Full request logging

### Squid Proxy Architecture

**Files:**
- `docker/proxy/Dockerfile`
- `docker/proxy/squid.conf`
- `docker/proxy/entrypoint.sh`

**Squid Configuration:**
```conf
# Only allow configured domains
acl allowed_domains dstdomain "/etc/squid/allowed-domains.txt"
http_access allow localnet allowed_domains
http_access deny all

# Full logging
access_log stdio:/var/log/squid/access.log
```

**Default Allowlist (scripts/utils/common-functions.sh):**
```bash
*.github.com
*.githubcopilot.com
*.nuget.org
*.npmjs.org
*.pypi.org
*.docker.io
registry-1.docker.io
learn.microsoft.com
# ... etc
```

**Architecture:**
```
[Agent Container] → [Squid Proxy Container] → Internet
       ↓                     ↓
   Log to stdout      Allowlist filter
                      + Access log
```

**Analysis:**
- ✅ Provides visibility into network requests
- ✅ Allowlist can be customized per-launch
- ✅ Logs contain full URLs (helpful for forensics)
- ⚠️ Logs may contain sensitive data
- ⚠️ Allowlist permits functional destinations
- ⚠️ Determined attacker could use allowed destinations for exfiltration

### Network Isolation Guarantees

**What Container Can Reach:**
- In allow-all: Any internet destination
- In squid: Only allowlisted domains
- In restricted: Nothing

**What Container Cannot Reach:**
- Host services (unless explicitly exposed)
- Other containers (unless on same network)
- Internal Docker network services

**Analysis:**
- ✅ Host isolation maintained
- ✅ Network policy configurable per-launch
- ✅ Squid mode provides good balance of functionality and visibility
- ⚠️ allow-all mode has no restrictions (by design)

## Git Workflow & Branch Isolation

### Branch Naming Strategy

**File:** `scripts/launchers/launch-agent` lines 224-270

**Pattern:** `<agent>/<branch-name>`

**Examples:**
- `copilot/session-1`
- `copilot/feature-auth`
- `codex/refactor-db`

**Analysis:**
- ✅ Clearly identifies agent-created branches
- ✅ Prevents naming conflicts between agents
- ✅ Easy to review/delete agent branches
- ✅ Git history shows which agent made changes

### Dual Remote Setup

**File:** `scripts/runtime/entrypoint.sh` (lines configuring git remotes)

**Configuration:**
```bash
# origin: GitHub or upstream repository
git remote add origin "$ORIGIN_URL"

# local: Host repository (for quick sync)
git remote add local "$LOCAL_REMOTE_URL"

# Default push to local (safe)
git config remote.pushDefault local
```

**Auto-Push on Shutdown (entrypoint.sh lines 8-78):**
```bash
cleanup_on_shutdown() {
    if [ "$AUTO_PUSH" = "true" ]; then
        git add -A
        git commit -m "$AUTO_COMMIT_MSG"
        git push local "$BRANCH"
    fi
}
trap cleanup_on_shutdown EXIT SIGTERM SIGINT
```

**Analysis:**
- ✅ Changes pushed to host repository by default
- ✅ Origin pushes are explicit (prevents accidental publication)
- ✅ Auto-commit preserves work on container shutdown
- ⚠️ Auto-push could push malicious changes to host repo
- ⚠️ Host repo then needs review before pushing to origin
- ✅ Can disable auto-push with `--no-push` flag

## Entry Point & Initialization

### Container Startup Sequence

**File:** `scripts/runtime/entrypoint.sh`

**Sequence:**
1. Copy source repo to /workspace (lines 158-162)
2. Setup git remotes (lines 164-180)
3. Checkout/create agent branch (lines 182-195)
4. Configure git credentials via proxy (lines 197-210)
5. Setup MCP configs (lines 212-225)
6. Load MCP secrets (lines 227-235)
7. Install .NET preview if requested (lines 237-245)
8. Start tmux session or exec command (lines 247+)

**Analysis:**
- ✅ Predictable, documented setup sequence
- ✅ Workspace isolation established early
- ✅ Git configured for safety (local as default remote)
- ✅ Credentials handled via proxy (not direct files)

## Resource Limits

**File:** `scripts/launchers/launch-agent` lines 612-618

**Applied Limits:**
```bash
--cpus=4        # Default: 4 cores
--memory=8g     # Default: 8GB RAM
```

**PowerShell also includes:**
```powershell
--pids-limit=4096  # Limit number of processes
```

**Analysis:**
- ✅ Prevents CPU exhaustion attacks
- ✅ Prevents memory exhaustion attacks
- ⚠️ Bash launcher missing pids-limit
- ⚠️ No disk I/O limits
- ⚠️ No network bandwidth limits

## MCP Server Configuration

### Config Flow

**Files:**
- `config.toml` (in workspace root)
- `scripts/utils/convert-toml-to-mcp.py`
- `scripts/runtime/setup-mcp-configs.sh`

**Process:**
1. User creates `config.toml` in repository
2. On container startup, script converts TOML to JSON
3. JSON placed in `~/.config/{copilot,codex,claude}/mcp/config.json`
4. Agents read JSON and start MCP servers

**Analysis:**
- ✅ MCP configs are per-workspace (in repo)
- ✅ Can be version-controlled
- ✅ No global MCP config modification
- ⚠️ Workspace can configure any MCP server
- ⚠️ MCPs run with same privileges as agent

## Summary: Current Security Posture

### Strong Points (Defense in Depth)

1. **Container Boundary:**
   - Non-root user
   - no-new-privileges enforced
   - No docker socket access
   - Resource limits

2. **Filesystem Isolation:**
   - Workspace copied (not mounted)
   - Auth configs read-only
   - No host filesystem access

3. **Network Controls:**
   - Configurable per-launch
   - Squid proxy for visibility
   - Restricted mode available

4. **Credential Security:**
   - Socket-based proxies
   - Read-only mounts
   - No credentials in images

5. **Reversibility:**
   - Branch isolation
   - Git history
   - Ephemeral containers

### Identified Gaps

1. **Critical:**
   - Capability drop missing in bash launcher (PowerShell has it)

2. **Important:**
   - No seccomp profile
   - No AppArmor profile
   - Pids-limit missing in bash launcher

3. **Nice-to-Have:**
   - No root filesystem read-only
   - No disk I/O limits
   - No tool classification/tiering
   - No unified audit logging

### Risk Classification

**Actual Risks Present:**
- Destructive changes within workspace (by design)
- Network data exfiltration in allow-all mode (by design)
- Malicious code injection into repo (requires review before merge)

**Theoretical Risks NOT Present:**
- Container escape (structurally blocked)
- Host filesystem modification (no host mounts)
- Credential modification (read-only mounts)
- Docker socket access (not mounted)
- Privilege escalation (no-new-privileges + non-root)

## Next Steps

See:
- `02-threat-model.md` for detailed threat analysis
- `03-tool-danger-matrix.md` for operation risk classification
- `04-hardened-architecture.md` for recommended enhancements
