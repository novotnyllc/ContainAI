# ContainAI Troubleshooting Guide

This guide helps you diagnose and resolve common issues with ContainAI. Scenarios are organized by the symptom you observe (error messages, behaviors) rather than by underlying cause.

## Quick Reference

Most common issues and their one-line fixes:

| Issue | Quick Fix |
|-------|-----------|
| SSH connection refused | `cai doctor fix --all` then retry |
| Host key verification failed | `cai ssh cleanup` then retry |
| Permission denied (publickey) | `cai run --fresh /workspace` to recreate container |
| Port already in use | Stop unused containers or adjust port range in config |
| Container won't start | Check logs with `docker logs <container>` |
| sshd not ready | Wait or check `docker exec <container> systemctl status ssh` |
| Updates available warning | Run `cai update` or set `CAI_UPDATE_CHECK_INTERVAL=never` |
| Claude OAuth token expired | Re-run `claude /login` inside container, or use API key |
| Files owned by nobody:nogroup | `cai doctor fix volume --all` (Linux/WSL2 only) |
| claude/bun command not found | Pull latest image: `cai shell --fresh /path/to/workspace` |
| Hostname differs from container name | Expected behavior - see [Hostname Issues](#hostname-issues) |
| SSH waits during --fresh | Expected behavior - see [Hostname Issues](#why-does-my-ssh-session-wait-during---fresh) |

**Quick Links:**
- [Diagnostic Commands](#diagnostic-commands)
- [SSH Connection Issues](#ssh-connection-issues)
- [Container Startup Issues](#container-startup-issues)
- [Permission Issues](#permission-issues)
- [Port Conflicts](#port-conflicts)
- [Host Key Verification Failed](#host-key-verification-failed)
- [Installation Issues](#installation-issues)
- [Sysbox/Secure Engine Issues](#sysboxsecure-engine-issues)
- [Volume Ownership Repair](#volume-ownership-repair-linuxwsl2-only)
- [Container Issues](#container-issues)
- [Configuration Issues](#configuration-issues)
- [Credential/Import Issues](#credentialimport-issues) (including [Claude OAuth Token Expiration](#claude-oauth-token-expiration-after-import))
- [Platform-Specific Issues](#platform-specific-issues)
- [Updates Available Warning](#updates-available-warning)
- [Shell Environment Issues](#shell-environment-issues) (command not found for claude, bun, etc.)
- [Hostname Issues](#hostname-issues) (hostname differs from container name)
- [Still Stuck?](#still-stuck)

---

## Diagnostic Commands

Before diving into specific issues, run these commands to gather diagnostic information:

```bash
# Full system health check (checks SSH, Docker, Sysbox)
cai doctor

# Auto-fix common issues (SSH keys, config, permissions)
cai doctor fix --all

# JSON output for scripting/debugging
cai doctor --json

# Clean up stale SSH configurations
cai ssh cleanup
```

### Understanding `cai doctor` Output

The `cai doctor` command checks your system's readiness for ContainAI:

| Status | Meaning |
|--------|---------|
| `[OK]` | Component is working correctly |
| `[WARN]` | Component has issues but may still work |
| `[ERROR]` | Component is broken and blocks usage |
| `[INFO]` | Informational note (not an error) |
| `[SKIP]` | Check was skipped due to earlier failure |

**Key sections in doctor output:**

1. **Docker** - CLI and daemon availability
2. **Sysbox Isolation** - Sysbox runtime and context availability
3. **Platform** - Platform-specific checks (WSL2 kernel/seccomp, macOS Lima)
4. **ContainAI Docker** - ContainAI docker-ce installation status
5. **SSH** - SSH key, config directory, Include directive, OpenSSH version, connectivity
6. **Resources** - Host memory/CPU and container limits
7. **Summary** - Overall readiness status (requires both Sysbox AND SSH)

---

## SSH Connection Issues

### "SSH connection refused"

**Symptom:**
```
ssh: connect to host localhost port 2301: Connection refused
```
or
```
[ERROR] SSH connection refused
```

**Diagnosis:**
```bash
# Check if container is running
docker --context containai-docker ps

# Check if sshd is running inside container
docker --context containai-docker exec <container-name> systemctl status ssh

# Check if port is listening
docker --context containai-docker exec <container-name> ss -tlnp | grep :22

# Check port mapping
docker --context containai-docker port <container-name> 22
```

**Likely causes:**
1. sshd service not running in container
2. Container not fully started
3. Port not exposed/mapped
4. Firewall blocking the port

**Solutions:**

1. **Wait for sshd to start** (containers need a few seconds after boot):
   ```bash
   # Retry in a few seconds
   cai shell /path/to/workspace
   ```

2. **Restart sshd in the container:**
   ```bash
   docker --context containai-docker exec <container-name> systemctl restart ssh
   ```

3. **Check if container started properly:**
   ```bash
   docker --context containai-docker logs <container-name>
   ```

4. **Recreate the container if sshd is broken:**
   ```bash
   cai run /path/to/workspace --fresh
   ```

### "Permission denied (publickey)"

**Symptom:**
```
agent@localhost: Permission denied (publickey).
```

**Diagnosis:**
```bash
# Verbose SSH to see what's happening
ssh -vv -p 2301 agent@localhost

# Check if SSH key exists
ls -la ~/.config/containai/id_containai

# Check if public key is in container
docker --context containai-docker exec <container-name> cat /home/agent/.ssh/authorized_keys
```

**Likely causes:**
1. SSH key not generated yet
2. Public key not injected into container
3. Wrong permissions on authorized_keys

**Solutions:**

1. **Run doctor fix to ensure SSH keys exist:**
   ```bash
   cai doctor fix --all
   ```

2. **Recreate container with fresh SSH setup (recommended):**
   ```bash
   cai run --fresh /path/to/workspace
   ```

3. **Manually inject the key (if container must be preserved):**
   ```bash
   # Get your public key
   cat ~/.config/containai/id_containai.pub

   # Add to container (as root)
   docker --context containai-docker exec <container-name> bash -c 'mkdir -p /home/agent/.ssh && chmod 700 /home/agent/.ssh'
   docker --context containai-docker exec <container-name> bash -c 'cat >> /home/agent/.ssh/authorized_keys' < ~/.config/containai/id_containai.pub
   docker --context containai-docker exec <container-name> chown -R agent:agent /home/agent/.ssh
   docker --context containai-docker exec <container-name> chmod 600 /home/agent/.ssh/authorized_keys
   ```

### "SSH connection timed out"

**Symptom:**
```
ssh: connect to host localhost port 2301: Connection timed out
```
or
```
[ERROR] sshd did not become ready within 30 seconds
```

**Diagnosis:**
```bash
# Check container state
docker --context containai-docker inspect <container-name> --format '{{.State.Status}}'

# Check systemd boot progress
docker --context containai-docker logs <container-name> 2>&1 | tail -50

# Check if port is correct
docker --context containai-docker inspect <container-name> --format '{{index .Config.Labels "containai.ssh-port"}}'
```

**Likely causes:**
1. Container systemd boot taking too long
2. Resource constraints (low memory/CPU)
3. Wrong port being used

**Solutions:**

1. **Wait longer and retry:**
   ```bash
   sleep 30
   cai shell /path/to/workspace
   ```

2. **Increase container resources in config:**
   ```toml
   # ~/.config/containai/config.toml
   [container]
   memory = "8g"
   cpus = 4
   ```

3. **Check container logs for boot issues:**
   ```bash
   docker --context containai-docker logs <container-name>
   ```

---

## Container Startup Issues

### "Container won't start"

**Symptom:**
Container exits immediately or fails to start.

**Diagnosis:**
```bash
# Check container state
docker --context containai-docker ps -a --filter "name=<container-name>"

# Check exit code and logs
docker --context containai-docker logs <container-name>

# Inspect container for issues
docker --context containai-docker inspect <container-name> --format '{{.State.ExitCode}} {{.State.Error}}'
```

**Common causes and solutions:**

1. **OOM (Out of Memory):**
   ```bash
   # Increase memory limit
   # In ~/.config/containai/config.toml:
   [container]
   memory = "8g"
   ```

2. **Sysbox runtime not found:**
   ```bash
   # Check Sysbox is installed
   docker info | grep sysbox-runc

   # If missing, run setup
   cai setup
   ```

3. **Port conflict:**
   ```bash
   # Check if port is in use
   ss -tlnp | grep 2300

   # Find available port
   cai doctor
   ```

### "systemd failed to start"

**Symptom:**
Container logs show systemd errors or container exits with code 1.

**Diagnosis:**
```bash
# Check systemd boot logs
docker --context containai-docker logs <container-name> 2>&1 | grep -i systemd

# Check for failed units
docker --context containai-docker exec <container-name> systemctl --failed
```

**Solutions:**

1. **Ensure Sysbox runtime is being used:**
   ```bash
   docker --context containai-docker inspect <container-name> --format '{{.HostConfig.Runtime}}'
   # Should show "sysbox-runc"
   ```

2. **Check container was created with correct context:**
   ```bash
   docker --context containai-docker ps
   ```

3. **Recreate with fresh state:**
   ```bash
   cai run /path/to/workspace --fresh
   ```

---

## Permission Issues

### "Permission denied accessing Docker"

**Symptom:**
```
[ERROR] Permission denied accessing Docker
```
or
```
Got permission denied while trying to connect to the Docker daemon socket
```

**Diagnosis:**
```bash
# Check docker group membership
groups

# Check socket permissions
ls -la /var/run/containai-docker.sock
```

**Solutions:**

1. **Add user to docker group:**
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker  # Apply immediately
   # or log out and back in
   ```

2. **Fix socket permissions:**
   ```bash
   sudo chmod 660 /var/run/containai-docker.sock
   sudo chgrp docker /var/run/containai-docker.sock
   ```

### "Permission denied inside container"

**Symptom:**
Commands inside container fail with permission errors.

**Diagnosis:**
```bash
# Check user inside container
docker --context containai-docker exec <container-name> id

# Check file ownership
docker --context containai-docker exec <container-name> ls -la /home/agent/workspace
```

**Solutions:**

1. **Files should be owned by agent user:**
   ```bash
   docker --context containai-docker exec <container-name> chown -R agent:agent /home/agent/workspace
   ```

2. **Volume mount permissions issue** - ensure host directory is readable:
   ```bash
   ls -la /path/to/workspace
   ```

---

## Port Conflicts

### "Port already in use"

**Symptom:**
```
[ERROR] All 201 SSH ports in range 2300-2500 are in use
```
or
```
Bind for 0.0.0.0:2301 failed: port is already allocated
```

**Diagnosis:**
```bash
# See what's using ContainAI ports
ss -tlnp | grep -E ':2[3-4][0-9]{2}|:2500'

# List ContainAI containers and their ports
docker --context containai-docker ps --filter "label=containai.managed=true" \
  --format '{{.Names}}: {{index .Labels "containai.ssh-port"}}'

# Check for orphaned containers
docker --context containai-docker ps -a --filter "label=containai.managed=true"
```

**Solutions:**

1. **Stop unused containers:**
   ```bash
   # List all ContainAI containers
   docker --context containai-docker ps -a --filter "label=containai.managed=true"

   # Stop specific container
   docker --context containai-docker stop <container-name>

   # Remove container (preserves data volume)
   docker --context containai-docker rm <container-name>
   ```

2. **Clean up stale SSH configs:**
   ```bash
   cai ssh cleanup
   ```

3. **Expand port range in config:**
   ```toml
   # ~/.config/containai/config.toml
   [ssh]
   port_range_start = 2300
   port_range_end = 3000
   ```

4. **Check for non-ContainAI processes using ports:**
   ```bash
   # Find what's using a specific port
   sudo lsof -i :2301
   ```

---

## Host Key Verification Failed

### "Host key verification failed"

**Symptom:**
```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Host key verification failed.
```
or
```
[WARN] SSH host key has changed for container <name>
```

**Diagnosis:**
```bash
# Check the known_hosts file
cat ~/.config/containai/known_hosts

# Check container's current host keys
docker --context containai-docker exec <container-name> cat /etc/ssh/ssh_host_ed25519_key.pub
```

**Expected behavior:** This happens when a container is recreated (with `--fresh`) because new containers generate new SSH host keys.

**Solutions:**

1. **Use --fresh to force clean state (recommended):**
   ```bash
   cai run /path/to/workspace --fresh
   ```

2. **Manually clean the old key:**
   ```bash
   ssh-keygen -R "[localhost]:2301" -f ~/.config/containai/known_hosts
   ```

3. **Clean all stale entries:**
   ```bash
   cai ssh cleanup
   ```

4. **If you suspect a security issue** (man-in-the-middle attack):
   - Don't connect
   - Verify container identity through Docker
   - Check container logs for suspicious activity

### "Known hosts file has wrong permissions"

**Symptom:**
```
Permissions for '/home/user/.config/containai/known_hosts' are too open.
```

**Solution:**
```bash
chmod 600 ~/.config/containai/known_hosts
chmod 700 ~/.config/containai
```

Or run:
```bash
cai doctor fix --all
```

---

## Installation Issues

### "Docker is not installed or not in PATH"

**Symptom:**
```
[ERROR] Docker is not installed or not in PATH
```

**Diagnosis:**
```bash
which docker
docker --version
```

**Solution:**

1. **Install Docker Desktop** (recommended for most users):
   - Download from https://www.docker.com/products/docker-desktop/
   - Follow installation instructions for your platform

2. **Or install Docker Engine** (Linux advanced users):
   ```bash
   # Ubuntu/Debian
   sudo apt-get update
   sudo apt-get install docker-ce docker-ce-cli containerd.io
   ```

3. **Add Docker to PATH** if installed but not found:
   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   export PATH="$PATH:/usr/local/bin"
   ```

### "No timeout command available"

**Symptom:**
```
[ERROR] No timeout command available (timeout, gtimeout, or perl required)
```

**Diagnosis:**
```bash
which timeout gtimeout perl
```

**Solution:**

**macOS:**
```bash
brew install coreutils
```

**Linux:**
```bash
# Ubuntu/Debian
sudo apt install coreutils
# or
sudo apt install perl
```

### "ripgrep (rg) is not installed"

**Symptom:**
```
rg: command not found
```

**Diagnosis:**
```bash
command -v rg
rg --version
```

**Solution:**

**macOS:**
```bash
brew install ripgrep
```

**Linux:**
```bash
sudo apt install ripgrep  # Ubuntu/Debian
sudo dnf install ripgrep  # Fedora
```

### "OpenSSH version too old"

**Symptom:**
```
[ERROR] OpenSSH version: 7.2
(OpenSSH 7.3+ required for Include directive)
```

**Diagnosis:**
```bash
ssh -V
```

**Solution:**

Update OpenSSH. On most systems:

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt upgrade openssh-client
```

**macOS:**
macOS 10.13+ includes a sufficiently new OpenSSH. If using an older version:
```bash
brew install openssh
```

---

## Sysbox/Secure Engine Issues

### "containai-docker context not found"

**Symptom:**
```
Sysbox available:                       [INFO] Not configured
(Run 'cai setup' to configure 'containai-docker' context)
```

**Diagnosis:**
```bash
docker context ls
```

**Solution:**

Run the setup command to configure Sysbox:
```bash
cai setup
```

This creates the `containai-docker` Docker context pointing to a Sysbox-enabled daemon.

### "Sysbox runtime not found"

**Symptom:**
```
(Sysbox runtime not found - run 'cai setup')
```

**Diagnosis:**
```bash
docker info --format '{{json .Runtimes}}'
```

**Solution:**

**Linux (native):**
```bash
# Install Sysbox
curl -fsSL https://get.nestybox.com/sysbox/install.sh | bash

# Verify installation
docker info | grep sysbox
```

**WSL2:**
```bash
# Sysbox must be installed inside WSL2
cai setup
```

**macOS:**
Sysbox is not natively supported on macOS. Use Docker Desktop with ECI instead, or configure a Lima VM with Sysbox.

### "Docker daemon for 'containai-docker' not running"

**Symptom:**
```
(Docker daemon for 'containai-docker' not running)
```

**Diagnosis:**
```bash
docker --context containai-docker info
```

**Solution:**

**WSL2:**
```bash
# Start the isolated Docker daemon
sudo systemctl start containai-docker
```

**Lima (macOS):**
```bash
limactl start containai-docker
```

### "containai-docker service not running"

**Symptom:**
```
[ERROR] containai-docker service not running
```

**Diagnosis:**
```bash
systemctl status containai-docker
ls -la /var/run/containai-docker.sock
```

**Solution:**
```bash
sudo systemctl start containai-docker
sudo systemctl enable containai-docker  # Auto-start on boot
```

---

## Volume Ownership Repair (Linux/WSL2 only)

### "Files owned by nobody:nogroup"

**Symptom:**
Inside a container, files appear owned by `nobody:nogroup`:
```bash
ls -la /home/agent/workspace
# Shows: nobody nogroup instead of agent agent
```

Or agents fail with permission errors when accessing their data volumes.

**Cause:**
This is **id-mapped mount corruption** - a known issue with Sysbox user namespace isolation. When containers are stopped uncleanly or there are filesystem consistency issues, the UID/GID mappings can become corrupted.

**Diagnosis:**
```bash
# List volumes and check for corruption
cai doctor fix volume

# Check specific volume
cai doctor fix volume myvolume
```

The repair scan looks for files owned by UID/GID 65534 (`nobody:nogroup`) in volume data paths.

**Solution:**

```bash
# Repair all managed container volumes
cai doctor fix volume --all

# Repair specific volume
cai doctor fix volume myvolume
```

**How repair works:**

1. Identifies ContainAI-managed containers (labeled `containai.managed=true`)
2. Detects target UID/GID from running container (or defaults to 1000:1000)
3. Finds corrupted files (owned by 65534:65534) in volume data paths
4. Runs `sudo chown` to fix ownership to the detected UID/GID
5. Reports if container rootfs is tainted (consider recreating)

**Repair output:**
```
ContainAI Doctor Fix (Volume: myproject-data)
=============================================

  Target ownership:                                1000:1000 (from container myproject-main)
  Volume path:                                     /var/lib/containai-docker/volumes/myproject-data/_data
  Corrupted files:                                 47 with nobody:nogroup
  Repairing...                                     [FIXED]
```

**When to recreate vs repair:**

| Situation | Action |
|-----------|--------|
| Only volume data corrupted | `cai doctor fix volume --all` |
| Rootfs also tainted | Recreate container with `cai run --fresh` |
| Corruption recurs | Investigate systemd/docker stop behavior |

**Platform note:** Volume repair is only available on Linux and WSL2. On macOS, volumes are inside the Lima VM and not directly accessible from the host.

---

## Container Issues

### "Image not found"

**Symptom:**
```
[ERROR] Image not found: ghcr.io/novotnyllc/containai/agents:latest
```

**Diagnosis:**
```bash
docker --context containai-docker images | grep containai
```

**Solution:**

Pull the required image:
```bash
docker --context containai-docker pull ghcr.io/novotnyllc/containai/agents:latest
```

### "Container exists but was not created by ContainAI"

**Symptom:**
```
[ERROR] Container 'myproject-main' exists but was not created by ContainAI

  Expected label 'containai.managed': true
  Actual label 'containai.managed':   <not set>
```

**Diagnosis:**
```bash
docker --context containai-docker inspect myproject-main --format '{{.Config.Labels}}'
```

**Cause:** A container with the same name already exists but wasn't created by ContainAI.

**Solution:**

Option 1: Use a different container name:
```bash
cai run /workspace --name my-unique-name
```

Option 2: Remove the conflicting container:
```bash
docker --context containai-docker rm -f myproject-main
```

### "Failed to create volume"

**Symptom:**
```
[ERROR] Failed to create volume containai-data
```

**Diagnosis:**
```bash
docker --context containai-docker volume ls
docker --context containai-docker volume inspect containai-data
```

**Solution:**

1. Check Docker daemon is running
2. Check disk space: `docker --context containai-docker system df`
3. Try creating manually:
   ```bash
   docker --context containai-docker volume create containai-data
   ```

---

## Configuration Issues

### "Config file not found"

**Symptom:**
```
[ERROR] Config file not found: /path/to/.containai/config.toml
```

**Diagnosis:**
```bash
ls -la /path/to/.containai/config.toml
```

**Cause:** Explicit `--config` path doesn't exist.

**Solution:**

1. Check the path exists:
   ```bash
   ls -la /path/to/.containai/config.toml
   ```

2. Create the config file:
   ```bash
   mkdir -p .containai
   cat > .containai/config.toml << 'EOF'
   [agent]
   data_volume = "my-project-data"
   EOF
   ```

### "Failed to parse config file"

**Symptom:**
```
[ERROR] Failed to parse config file: .containai/config.toml
```

**Diagnosis:**

Check TOML syntax:
```bash
cai config list
```

**Common causes:**
- Missing quotes around string values
- Invalid TOML syntax
- Incorrect section names

**Solution:**

Fix the TOML syntax. Example valid config:
```toml
[agent]
data_volume = "my-project-data"
default = "claude"

[ssh]
port_range_start = 2300
port_range_end = 2500
forward_agent = false

[container]
memory = "8g"
cpus = 4
```

---

## Credential/Import Issues

### Claude OAuth Token Expiration After Import

**Symptom:**
```
API Error: 401 {"type":"error","error":{"type":"authentication_error","message":"OAuth token has expired. Please obtain a new token or refresh your existing token."},...} · Please run /login
```
or
```
OAuth error: ECONNREFUSED
```

**Background:**

Claude Code uses OAuth tokens stored in `~/.claude/.credentials.json`. These tokens have several characteristics that affect their usability in containerized environments:

1. **Token Lifetime**: Access tokens expire within 8-12 hours. The `expiresAt` field is in **milliseconds since epoch** (Unix timestamp * 1000).

2. **Refresh Tokens**: The refresh token (`sk-ant-ort01-...`) can obtain new access tokens, but only when the Claude CLI's refresh mechanism can connect to Anthropic's servers.

3. **Session State**: Claude CLI maintains additional session state in `~/.claude/statsig/` for feature flags and analytics.

**Root Causes:**

1. **Token Already Expired at Import Time**: If the source token is near expiration when imported, it may expire before first use in the container.

2. **Refresh Token Rotation**: Claude uses refresh token rotation - when a refresh token is used, it's invalidated and a new one is issued. If multiple Claude instances (host and container) use the same refresh token, only one will succeed and the other will have an invalid token.

3. **Server-Side Issues**: Anthropic's OAuth infrastructure occasionally has issues that cause valid tokens to be rejected (see [GitHub Issue #19078](https://github.com/anthropics/claude-code/issues/19078)).

4. **Multiple Instances Conflict**: Running Claude on both host and container simultaneously can cause refresh token conflicts, as each instance may try to refresh and invalidate the other's token.

**Diagnosis:**
```bash
# Check token expiration time (expiresAt is in milliseconds)
jq '.claudeAiOauth.expiresAt' ~/.claude/.credentials.json
# Compare to current time in milliseconds
echo $(($(date +%s) * 1000))

# Check if container clock is synchronized
docker exec <container> date
date

# Check for multiple Claude instances
ps aux | grep claude
```

**Solutions:**

1. **Re-authenticate inside the container** (most reliable):
   ```bash
   # Inside the container
   claude /login
   ```
   This generates fresh tokens bound to the container's session.

2. **Import fresh credentials immediately before use**:
   ```bash
   # On host: re-authenticate
   claude /login

   # Then immediately import
   cai import

   # Use container within a few hours
   ```

3. **Kill conflicting Claude processes**:
   ```bash
   # If using OAuth authentication on both host and container
   pkill -f claude  # On host
   # Then use only in container
   ```

4. **Use API key instead of OAuth** (for automation):
   ```bash
   # Set ANTHROPIC_API_KEY in container .env
   # This bypasses OAuth entirely
   ```

**Known Limitations:**

- OAuth tokens are designed for interactive use, not automated/containerized workflows
- Token refresh requires network access to Anthropic's servers
- Sharing credentials between host and container is inherently fragile due to refresh token rotation
- Anthropic's OAuth infrastructure occasionally has server-side issues that require waiting

**Workaround for Automated/CI Environments:**

For reliable automated access, use an API key (`ANTHROPIC_API_KEY`) instead of OAuth. OAuth tokens are designed for interactive sessions and don't reliably persist across environment boundaries.

---

### Stale or corrupted credentials in sandbox

**Symptom:**

Agent fails to authenticate, shows credential errors, or uses outdated tokens:
```
[ERROR] Authentication failed
```
or
```
[ERROR] Invalid credentials
```
or agent cannot access GitHub, APIs, or other services that previously worked.

**Diagnosis:**
```bash
# Check volume contents for credential files
docker --context containai-docker run --rm -v containai-data:/data alpine ls -la /data/claude/
docker --context containai-docker run --rm -v containai-data:/data alpine ls -la /data/config/gh/
```

**Solution:**

Re-import fresh credentials from host:
```bash
cai import
```

### "Rsync sync failed"

**Symptom:**
```
[ERROR] Rsync sync failed
```

**Diagnosis:**
```bash
# Check if rsync image is available
docker --context containai-docker pull instrumentisto/rsync-ssh

# Check volume status
docker --context containai-docker volume inspect containai-data
```

**Solution:**

1. Ensure Docker daemon is running
2. Pull the rsync image:
   ```bash
   docker --context containai-docker pull instrumentisto/rsync-ssh
   ```
3. Check disk space: `docker --context containai-docker system df`
4. (Optional) Override the image used by import:
   ```bash
   export CONTAINAI_RSYNC_IMAGE=instrumentisto/rsync-ssh
   ```

---

## Platform-Specific Issues

### WSL2: "Seccomp compatibility: warning"

**Symptom:**
```
Seccomp compatibility: warning           [WARN]
(WSL 1.1.0+ may have seccomp conflicts with Sysbox)
```

**Cause:** WSL2 kernel 1.1.0+ uses seccomp filter mode (mode 2) which can conflict with Sysbox.

**Diagnosis:**
```bash
grep Seccomp /proc/self/status
# Seccomp:   2  means filter mode (potential issues)
# Seccomp:   0 or 1  means no issues
```

**Solution:**

1. **Try running anyway** - many setups work despite the warning
2. **Use `--force`** if Sysbox fails:
   ```bash
   cai setup --force
   ```

### WSL2: "Docker context issue"

**Symptom:**
```
[ERROR] Docker context or connection issue
```

**Diagnosis:**
```bash
echo $DOCKER_CONTEXT $DOCKER_HOST
docker context ls
```

**Solution:**

Reset to default context:
```bash
unset DOCKER_CONTEXT DOCKER_HOST
docker context use default
```

### Linux: Permission denied

**Symptom:**
```
[ERROR] Permission denied accessing Docker
```

**Diagnosis:**
```bash
groups
ls -l /var/run/containai-docker.sock
sudo systemctl status containai-docker
```

**Solution:**

Add user to docker group and ensure the ContainAI Docker service is running:
```bash
sudo usermod -aG docker $USER
newgrp docker  # Apply immediately
# or log out and back in

# Ensure the isolated Docker service is running
sudo systemctl start containai-docker
```

---

## Shell Environment Issues

### "Command not found" for claude, bun, uv, etc.

**Symptom:**
```
claude: command not found
```
or
```
bun: command not found
```

**Background: How `cai shell` Connects**

When you run `cai shell`, ContainAI connects to the container via SSH and starts a login shell:

1. **Connection pathway**: `cai shell` -> SSH to container (port 2300-2500) -> `exec $SHELL -l`
2. **Shell initialization**: The `-l` flag makes bash source login shell init files
3. **Init file order**: `/etc/profile` -> (`~/.bash_profile` OR `~/.bash_login` OR `~/.profile`)

**Key insight**: Bash login shells source `/etc/profile` first, which in turn sources all files in `/etc/profile.d/*.sh`. ContainAI sets PATH in `/etc/profile.d/containai-agent-path.sh` to ensure tools are always available regardless of user shell config.

**Likely causes:**
1. Container image missing PATH configuration (older image version)
2. Custom `~/.bash_profile` that overwrites PATH without preserving `$PATH`
3. Shell not running as login shell

**Diagnosis:**
```bash
# Check PATH inside container (use printenv, not echo, for proper expansion)
cai exec -- printenv PATH

# Check if profile.d script exists
cai exec -- cat /etc/profile.d/containai-agent-path.sh

# Check which shell init files exist
cai exec -- bash -lc 'ls -la ~/.bash_profile ~/.bash_login ~/.profile 2>/dev/null || echo "No user profile files"'

# Verify claude location
cai exec -- command -v claude
cai exec -- ls -la /home/agent/.local/bin/claude
```

**Solutions:**

1. **Update container image** (recommended):
   ```bash
   # Pull latest image and recreate container
   docker --context containai-docker pull ghcr.io/novotnyllc/containai/agents:latest
   cai shell --fresh /path/to/workspace
   ```

2. **Manual PATH fix** (temporary):
   ```bash
   # Inside container, add to the appropriate profile file
   # If ~/.bash_profile exists, add there; otherwise add to ~/.profile
   if [ -f ~/.bash_profile ]; then
       echo 'export PATH="/home/agent/.local/bin:/home/agent/.bun/bin:$PATH"' >> ~/.bash_profile
   else
       echo 'export PATH="/home/agent/.local/bin:/home/agent/.bun/bin:$PATH"' >> ~/.profile
   fi
   ```

3. **Verify login shell** (for debugging):
   ```bash
   # Inside container
   shopt -q login_shell && echo "Login shell" || echo "Not login shell"
   ```

**Technical Details:**

The container image configures PATH in `/etc/profile.d/containai-agent-path.sh`:
```bash
# Sourced by /etc/profile for all login shells
if [ "$(id -u)" = "1000" ] || [ "$(id -un)" = "agent" ]; then
    export PATH="/home/agent/.local/bin:/home/agent/.bun/bin:${PATH}"
fi
```

This is more robust than using `~/.profile` because:
- `/etc/profile` is sourced BEFORE user profile files (`~/.bash_profile`, `~/.profile`)
- User profile files could overwrite PATH without preserving the system-set value
- `/etc/profile.d/` scripts are always sourced via `/etc/profile`

---

## Hostname Issues

### "Why does my hostname differ from my container name?"

**Symptom:**
```bash
$ hostname
my-workspace-main
# But container name is: my_workspace-main
```

**Explanation:**

ContainAI sets each container's hostname to a sanitized version of its name to ensure RFC 1123 compliance. UNIX hostnames have stricter requirements than Docker container names.

**What's happening:**

The hostname sanitization rules transform the container name:

| Container Name | Hostname | Transformation Applied |
|----------------|----------|------------------------|
| `my_workspace` | `my-workspace` | Underscores → hyphens |
| `MyProject` | `myproject` | Uppercase → lowercase |
| `app@v2.0` | `appv20` | Invalid chars removed |
| `test--app` | `test-app` | Multiple hyphens collapsed |

**RFC 1123 Rules:**

Valid hostnames must:
- Contain only lowercase letters, numbers, and hyphens
- Start and end with alphanumeric characters (no leading/trailing hyphens)
- Be 63 characters or fewer

**This is by design:**

The hostname is set via Docker's `--hostname` flag during container creation to ensure network compatibility. Tools like `hostname`, shell prompts (PS1), and network services use this value.

**Why this matters:**

- Some tools and scripts expect valid RFC 1123 hostnames
- Network services require compliant hostnames for proper DNS resolution
- Container names can include underscores, but hostnames cannot

**No action needed:**

This is expected behavior. To see both values:
```bash
# Get the Docker container name (from host)
docker --context containai-docker ps --filter "label=containai.managed=true" --format '{{.Names}}'

# Get the hostname (from inside the container)
hostname  # Returns the sanitized RFC 1123 hostname
```

Note: The container name and hostname may differ due to sanitization (e.g., underscores become hyphens).

### "Why does my SSH session wait during --fresh?"

**Symptom:**
```
cai shell --fresh /path/to/workspace
# (brief pause before connection)
```

**Explanation:**

When using `--fresh` or `--reset`, ContainAI destroys the existing container and creates a new one. The new container must boot systemd, start sshd, and generate new host keys before SSH can connect.

**What's happening:**

1. Old container is removed
2. New container is created with fresh state
3. systemd boots as PID 1
4. `ssh-keygen.service` generates new host keys
5. `containai-init.service` sets up workspace symlinks
6. `ssh.service` starts
7. CLI waits for sshd to accept connections (up to 60 seconds with exponential backoff)
8. Old known_hosts entries are automatically cleaned
9. SSH connects to the fresh container

**This is normal:** The brief pause (typically 5-15 seconds) is expected behavior. The CLI waits gracefully rather than failing with "connection refused" errors.

**If it takes longer than expected:**
- Check container logs: `docker --context containai-docker logs <container>`
- Increase resources in config if system is resource-constrained
- See [Container Startup Issues](#container-startup-issues) for boot problems

---

## SSH Debugging Commands

When troubleshooting SSH issues, these commands provide detailed diagnostic information:

```bash
# Verbose SSH connection (shows handshake details)
ssh -vv -p 2301 agent@localhost

# Check what keys SSH is offering
ssh-add -l

# Test SSH connection with specific key
ssh -i ~/.config/containai/id_containai -p 2301 agent@localhost

# Scan container's SSH host keys
ssh-keyscan -p 2301 localhost

# Check SSH config file parsing
ssh -G <container-name>

# Check sshd status inside container
docker --context containai-docker exec <container> systemctl status ssh

# Check sshd logs inside container
docker --context containai-docker exec <container> journalctl -u ssh -n 50

# Check listening ports inside container
docker --context containai-docker exec <container> ss -tlnp

# Check authorized_keys inside container
docker --context containai-docker exec <container> cat /home/agent/.ssh/authorized_keys

# Check SSH host keys inside container
docker --context containai-docker exec <container> ls -la /etc/ssh/ssh_host_*
```

---

## Updates Available Warning

### "Updates available" message

**Symptom:**
```
[WARN] Dockerd bundle update available: 27.3.1 -> 27.4.0
       Updating will stop running containers.
       Run: cai update
```

**Explanation:**

ContainAI periodically checks for newer versions of the managed dockerd bundle. This warning indicates a new version is available.

**What this means:**
- A newer version of the Docker daemon bundle is available
- Your current installation will continue to work normally
- The warning is informational and does not block any commands

**How to apply updates:**

```bash
cai update
```

**Important:** Updating the dockerd bundle will restart the `containai-docker` service. This means:
- All running containers will be stopped
- Containers will restart after the update completes
- Any unsaved work in containers may be lost

The update process:
1. Downloads the new dockerd bundle
2. Prompts for confirmation (unless `--force` is used)
3. Atomically swaps symlinks to the new version
4. Restarts the `containai-docker` service

**How to disable update checks:**

If you prefer not to see update warnings:

```bash
# Disable for current session
CAI_UPDATE_CHECK_INTERVAL=never cai doctor

# Disable permanently in config
# Add to ~/.config/containai/config.toml:
[update]
check_interval = "never"
```

**Network errors:**

If the update check fails due to network issues, ContainAI will:
- Not display any warning (fails silently)
- Not block the current command
- Retry on the next interval

The check uses a 5-second connect timeout to avoid delays. If you're behind a proxy that blocks access to `download.docker.com`, the update check will simply be skipped.

---

## Still Stuck?

If you've tried the solutions above and are still experiencing issues:

### 1. Gather Diagnostic Information

```bash
# Full doctor output
cai doctor 2>&1 | tee doctor-output.txt

# Docker info
docker info 2>&1 | tee docker-info.txt

# Environment
env | grep -E 'DOCKER|CONTAINAI' | tee env-output.txt

# Versions
docker version 2>&1 | tee versions.txt
ssh -V 2>&1 >> versions.txt
echo "cai version: $(cai --version 2>/dev/null || echo 'unknown')" >> versions.txt

# SSH config status
ls -la ~/.ssh/containai.d/ 2>&1 | tee ssh-config.txt
cat ~/.config/containai/known_hosts 2>&1 | tee known-hosts.txt
```

### 2. Check GitHub Issues

Search existing issues for your error message:
https://github.com/novotnyllc/ContainAI/issues

### 3. Open a New Issue

If your issue isn't documented, open a GitHub issue with:

1. **Error message** (exact text)
2. **Doctor output** (`cai doctor`)
3. **Steps to reproduce**
4. **Platform** (macOS/Linux/WSL2)
5. **Docker version** (`docker version`)
6. **SSH version** (`ssh -V`)

### 4. Community Support

- **GitHub Discussions**: For questions and community help
- **Pull Requests**: Contributions welcome!

---

## Appendix: Error Message Reference

Quick reference of error messages and their section in this guide:

| Error Message | Section |
|---------------|---------|
| "SSH connection refused" | [SSH Connection Issues](#ssh-connection-refused) |
| "Permission denied (publickey)" | [SSH Connection Issues](#permission-denied-publickey) |
| "SSH connection timed out" | [SSH Connection Issues](#ssh-connection-timed-out) |
| "Host key verification failed" | [Host Key Verification Failed](#host-key-verification-failed) |
| "sshd did not become ready" | [SSH Connection Issues](#ssh-connection-timed-out) |
| "Port already in use" | [Port Conflicts](#port-already-in-use) |
| "All SSH ports in range are in use" | [Port Conflicts](#port-already-in-use) |
| "Container won't start" | [Container Startup Issues](#container-wont-start) |
| "systemd failed to start" | [Container Startup Issues](#systemd-failed-to-start) |
| "Docker is not installed" | [Installation Issues](#docker-is-not-installed-or-not-in-path) |
| "No timeout command available" | [Installation Issues](#no-timeout-command-available) |
| "ripgrep (rg) is not installed" | [Installation Issues](#ripgrep-rg-is-not-installed) |
| "OpenSSH version too old" | [Installation Issues](#openssh-version-too-old) |
| "containai-docker context not found" | [Sysbox Issues](#containai-docker-context-not-found) |
| "Sysbox runtime not found" | [Sysbox Issues](#sysbox-runtime-not-found) |
| "Docker daemon not running" | [Sysbox Issues](#docker-daemon-for-containai-docker-not-running) |
| "containai-docker service not running" | [Sysbox Issues](#containai-docker-service-not-running) |
| "Image not found" | [Container Issues](#image-not-found) |
| "Container exists but was not created by ContainAI" | [Container Issues](#container-exists-but-was-not-created-by-containai) |
| "Failed to create volume" | [Container Issues](#failed-to-create-volume) |
| "Config file not found" | [Configuration Issues](#config-file-not-found) |
| "Failed to parse config file" | [Configuration Issues](#failed-to-parse-config-file) |
| "Authentication failed" / "Invalid credentials" | [Credential Issues](#stale-or-corrupted-credentials-in-sandbox) |
| "OAuth token has expired" | [Claude OAuth Token Expiration](#claude-oauth-token-expiration-after-import) |
| "Rsync sync failed" | [Credential Issues](#rsync-sync-failed) |
| "Seccomp compatibility: warning" | [WSL2 Issues](#wsl2-seccomp-compatibility-warning) |
| "Docker context issue" | [WSL2 Issues](#wsl2-docker-context-issue) |
| "Permission denied" | [Permission Issues](#permission-issues) |
| "Dockerd bundle update available" | [Updates Available Warning](#updates-available-message) |
| "Files owned by nobody:nogroup" | [Volume Ownership Repair](#files-owned-by-nobodynogroup) |
| "claude: command not found" | [Shell Environment Issues](#command-not-found-for-claude-bun-uv-etc) |
| "bun: command not found" | [Shell Environment Issues](#command-not-found-for-claude-bun-uv-etc) |
| Hostname differs from container name | [Hostname Issues](#why-does-my-hostname-differ-from-my-container-name) |
| SSH waits during --fresh/--reset | [Hostname Issues](#why-does-my-ssh-session-wait-during---fresh) |
