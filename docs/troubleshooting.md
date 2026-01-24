# ContainAI Troubleshooting Guide

This guide helps you diagnose and resolve common issues with ContainAI. Scenarios are organized by the symptom you observe (error messages, behaviors) rather than by underlying cause.

## Quick Reference

Most common issues and their one-line fixes:

| Issue | Quick Fix |
|-------|-----------|
| SSH connection refused | `cai doctor --fix` then retry |
| Host key verification failed | `cai ssh cleanup` then retry |
| Permission denied (publickey) | `cai run --fresh /workspace` to recreate container |
| Port already in use | Stop unused containers or adjust port range in config |
| Container won't start | Check logs with `docker logs <container>` |
| sshd not ready | Wait or check `docker exec <container> systemctl status ssh` |

**Quick Links:**
- [Diagnostic Commands](#diagnostic-commands)
- [SSH Connection Issues](#ssh-connection-issues)
- [Container Startup Issues](#container-startup-issues)
- [Permission Issues](#permission-issues)
- [Port Conflicts](#port-conflicts)
- [Host Key Verification Failed](#host-key-verification-failed)
- [Installation Issues](#installation-issues)
- [Sysbox/Secure Engine Issues](#sysboxsecure-engine-issues)
- [Container Issues](#container-issues)
- [Configuration Issues](#configuration-issues)
- [Credential/Import Issues](#credentialimport-issues)
- [Platform-Specific Issues](#platform-specific-issues)
- [Still Stuck?](#still-stuck)

---

## Diagnostic Commands

Before diving into specific issues, run these commands to gather diagnostic information:

```bash
# Full system health check (checks SSH, Docker, Sysbox)
cai doctor

# Auto-fix common issues (SSH keys, config, permissions)
cai doctor --fix

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
   cai doctor --fix
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
cai doctor --fix
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

### "jq is not installed"

**Symptom:**
```
[ERROR] jq is not installed (required for JSON processing)
```

**Diagnosis:**
```bash
which jq
jq --version
```

**Solution:**

**macOS:**
```bash
brew install jq
```

**Linux:**
```bash
sudo apt install jq  # Ubuntu/Debian
sudo dnf install jq  # Fedora
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
# Start the dedicated dockerd
sudo systemctl start containai-docker
# or
sudo dockerd --host unix:///var/run/containai-docker.sock &
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

## Container Issues

### "Image not found"

**Symptom:**
```
[ERROR] Image not found: ghcr.io/novotnyllc/containai/full:latest
```

**Diagnosis:**
```bash
docker --context containai-docker images | grep containai
```

**Solution:**

Pull the required image:
```bash
docker --context containai-docker pull ghcr.io/novotnyllc/containai/full:latest
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
[ERROR] Failed to create volume sandbox-agent-data
```

**Diagnosis:**
```bash
docker --context containai-docker volume ls
docker --context containai-docker volume inspect sandbox-agent-data
```

**Solution:**

1. Check Docker daemon is running
2. Check disk space: `docker --context containai-docker system df`
3. Try creating manually:
   ```bash
   docker --context containai-docker volume create sandbox-agent-data
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
python3 -c "import tomllib; tomllib.load(open('.containai/config.toml', 'rb'))"
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
docker --context containai-docker run --rm -v sandbox-agent-data:/data alpine ls -la /data/claude/
docker --context containai-docker run --rm -v sandbox-agent-data:/data alpine ls -la /data/config/gh/
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
docker --context containai-docker pull eeacms/rsync

# Check volume status
docker --context containai-docker volume inspect sandbox-agent-data
```

**Solution:**

1. Ensure Docker daemon is running
2. Pull the rsync image:
   ```bash
   docker --context containai-docker pull eeacms/rsync
   ```
3. Check disk space: `docker --context containai-docker system df`

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
ls -l /var/run/docker.sock
```

**Solution:**

Add user to docker group:
```bash
sudo usermod -aG docker $USER
newgrp docker  # Apply immediately
# or log out and back in
```

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
| "jq is not installed" | [Installation Issues](#jq-is-not-installed) |
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
| "Rsync sync failed" | [Credential Issues](#rsync-sync-failed) |
| "Seccomp compatibility: warning" | [WSL2 Issues](#wsl2-seccomp-compatibility-warning) |
| "Docker context issue" | [WSL2 Issues](#wsl2-docker-context-issue) |
| "Permission denied" | [Permission Issues](#permission-issues) |
