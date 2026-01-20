# ContainAI Troubleshooting Guide

This guide helps you diagnose and resolve common issues with ContainAI. Scenarios are organized by the symptom you observe (error messages, behaviors) rather than by underlying cause.

**Quick Links:**
- [Diagnostic Commands](#diagnostic-commands)
- [Installation Issues](#installation-issues)
- [Docker Desktop Issues](#docker-desktop-issues)
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
# Full system health check
cai doctor

# JSON output for scripting/debugging
cai doctor --json

# Check Docker version and context
docker version
docker context ls
docker info

# Check active context
echo $DOCKER_CONTEXT $DOCKER_HOST
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
2. **Docker Desktop (ECI Path)** - Version, sandboxes feature, ECI status
3. **Secure Engine (Sysbox Path)** - Sysbox runtime and context availability
4. **Platform** - Platform-specific checks (WSL2 seccomp, macOS ECI)
5. **Summary** - Overall isolation status and recommendations

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

---

## Docker Desktop Issues

### "Docker Desktop is not running"

**Symptom:**
```
[ERROR] Docker Desktop is not running
```
or
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
```

**Solution:**

1. **macOS:** Open Docker Desktop from Applications
2. **Windows/WSL2:** Start Docker Desktop from the Start menu
3. **Linux:**
   ```bash
   # If using Docker Desktop
   systemctl --user start docker-desktop

   # If using Docker Engine
   sudo systemctl start docker
   ```

4. Wait for Docker to fully start (whale icon stops animating)

### "Docker Desktop 4.50+ required"

**Symptom:**
```
[ERROR] Docker Desktop 4.50+ required (found: 4.35.1)
```

**Solution:**

1. Open Docker Desktop
2. Click the gear icon (Settings)
3. Go to "Software updates"
4. Click "Check for updates"
5. Install the update and restart Docker Desktop

Alternatively, download the latest version from:
https://www.docker.com/products/docker-desktop/

### "docker sandbox command not found"

**Symptom:**
```
[ERROR] docker sandbox command not found - enable experimental features
```

**Solution:**

1. Open Docker Desktop
2. Go to Settings > Features in development
3. Enable "Beta features" or "Experimental features"
4. Click "Apply & Restart"

See: https://docs.docker.com/ai/sandboxes/troubleshooting/

### "Docker Sandboxes feature is not enabled"

**Symptom:**
```
[ERROR] Docker Sandboxes feature is not enabled
```

**Diagnosis:**
```bash
docker sandbox ls
```

**Solution:**

1. Open Docker Desktop Settings
2. Go to "Features in development"
3. Enable "Docker sandboxes" or "AI sandbox" feature
4. Click "Apply & Restart"

### "Sandboxes disabled by administrator policy"

**Symptom:**
```
[ERROR] Sandboxes disabled by administrator policy
```

**Solution:**

Your organization's Docker Desktop administrator has disabled sandbox features. Contact your IT administrator to:

1. Enable beta features in Settings Management policy
2. Or provide an exception for your user

See: https://docs.docker.com/desktop/settings-and-maintenance/settings/

### "ECI available but not enabled"

**Symptom:**
```
ECI (Enhanced Container Isolation):     [WARN] Available but not enabled
```

**Solution:**

ECI requires Docker Business subscription. To enable:

1. Open Docker Desktop Settings
2. Go to Security
3. Enable "Enhanced Container Isolation"
4. Click "Apply & Restart"

Note: ECI is not strictly required if you have Sysbox configured as an alternative.

### "Docker command timed out"

**Symptom:**
```
[ERROR] Docker command timed out
```

**Diagnosis:**
```bash
# Check if daemon is responsive
docker info

# Check system resources
docker system df
```

**Solution:**

1. Restart Docker Desktop
2. If problem persists, check system resources (CPU, memory, disk)
3. Clear unused Docker resources:
   ```bash
   docker system prune -a
   ```

---

## Sysbox/Secure Engine Issues

### "containai-secure context not found"

**Symptom:**
```
Sysbox available:                       [INFO] Not configured
(Run 'cai setup' to configure 'containai-secure' context)
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

This creates the `containai-secure` Docker context pointing to a Sysbox-enabled daemon.

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

### "Docker daemon for 'containai-secure' not running"

**Symptom:**
```
(Docker daemon for 'containai-secure' not running)
```

**Diagnosis:**
```bash
docker --context containai-secure info
```

**Solution:**

**WSL2:**
```bash
# Start the dedicated dockerd
sudo systemctl start docker-containai
# or
sudo dockerd --host unix:///var/run/docker-containai.sock &
```

**Lima (macOS):**
```bash
limactl start containai-secure
```

### "Socket not found"

**Symptom:**
```
(Run 'cai setup' to install Sysbox)
```

**Diagnosis:**
```bash
# Check expected socket location
ls -la /var/run/docker-containai.sock  # WSL2
ls -la ~/.lima/containai-secure/sock/docker.sock  # macOS
```

**Solution:**

Run setup to create the socket and daemon configuration:
```bash
cai setup
```

---

## Container Issues

### "Image not found"

**Symptom:**
```
[ERROR] Image not found: docker/sandbox-templates:claude-code
```

**Solution:**

Pull the required image:
```bash
docker pull docker/sandbox-templates:claude-code
```

For Sysbox mode, pull to the correct context:
```bash
docker --context containai-secure pull docker/sandbox-templates:claude-code
```

### "Container exists but was not created by ContainAI"

**Symptom:**
```
[ERROR] Container 'myproject-main' exists but was not created by ContainAI

  Expected label 'containai.sandbox': containai
  Actual label 'containai.sandbox':   <not set>
```

**Cause:** A container with the same name already exists but wasn't created by ContainAI.

**Solution:**

Option 1: Use a different container name:
```bash
cai run --name my-unique-name
```

Option 2: Remove the conflicting container:
```bash
docker rm -f myproject-main
```

Option 3: Recreate as ContainAI-managed:
```bash
cai run --restart
```

### "Image mismatch prevents attachment"

**Symptom:**
```
[WARN] Container image mismatch:
  Running:   docker/sandbox-templates:gemini-cli
  Requested: docker/sandbox-templates:claude-code
[ERROR] Image mismatch prevents attachment.
```

**Cause:** Container was created with a different agent/image than requested.

**Solution:**

Recreate the container with the correct image:
```bash
cai run --restart
```

Or specify a different container name:
```bash
cai run --name claude-sandbox --agent claude
```

### "Volume mismatch prevents attachment"

**Symptom:**
```
[WARN] Data volume mismatch:
  Running:   project-a-data
  Requested: project-b-data
```

**Cause:** Container was created with a different data volume.

**Solution:**

Recreate the container:
```bash
cai run --restart
```

Or use a different container name:
```bash
cai run --name project-b-sandbox
```

### "Failed to create volume"

**Symptom:**
```
[ERROR] Failed to create volume sandbox-agent-data
```

**Diagnosis:**
```bash
docker volume ls
docker volume inspect sandbox-agent-data
```

**Solution:**

1. Check Docker daemon is running
2. Check disk space: `docker system df`
3. Try creating manually:
   ```bash
   docker volume create sandbox-agent-data
   ```

### "Invalid volume name"

**Symptom:**
```
[ERROR] Invalid volume name: my volume
```

**Cause:** Volume names must start with alphanumeric and contain only `[a-zA-Z0-9_.-]`.

**Solution:**

Use a valid volume name:
```bash
cai run --data-volume my-volume  # Valid
cai run --data-volume my_volume  # Valid
cai run --data-volume my.volume  # Valid
```

### "Unexpected container state"

**Symptom:**
```
[ERROR] Unexpected container state: paused
```

**Solution:**

Unpause or remove the container:
```bash
docker unpause <container-name>
# or
docker rm -f <container-name>
cai run
```

---

## Configuration Issues

### "Config file not found"

**Symptom:**
```
[ERROR] Config file not found: /path/to/.containai/config.toml
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

[workspace."/home/user/projects/myproject"]
data_volume = "myproject-data"
excludes = ["*.log", "node_modules/"]
```

### "Python required to parse config"

**Symptom:**
```
[ERROR] Python required to parse config: .containai/config.toml
```

**Solution:**

Install Python 3:

**macOS:**
```bash
brew install python3
```

**Linux:**
```bash
sudo apt install python3
```

### "Invalid workspace path"

**Symptom:**
```
[WARN] Invalid workspace path, using $PWD: /nonexistent/path
```

**Solution:**

Ensure the workspace path exists:
```bash
mkdir -p /path/to/workspace
cai run --workspace /path/to/workspace
```

### "Workspace path does not exist"

**Symptom:**
```
[ERROR] Workspace path does not exist: /path/to/workspace
```

**Solution:**

Create the directory or use an existing path:
```bash
mkdir -p /path/to/workspace
```

---

## Credential/Import Issues

### "--credentials=host requires acknowledgement"

**Symptom:**
```
[ERROR] --credentials=host requires --acknowledge-credential-risk
```

**Cause:** Host credential sharing requires explicit acknowledgement.

**Solution:**

Add the acknowledgement flag:
```bash
cai run --credentials host --acknowledge-credential-risk
```

Or use the new explicit flags:
```bash
cai run --allow-host-credentials --i-understand-this-exposes-host-credentials
```

**Warning:** This shares your `~/.ssh`, `~/.gitconfig`, and other credentials with the sandbox.

### "--credentials=host only supported in ECI mode"

**Symptom:**
```
[ERROR] --credentials=host / --allow-host-credentials is only supported in ECI mode (Docker Desktop)

Current mode: Sysbox (context: containai-secure)
```

**Cause:** Host credential sharing is a Docker Desktop sandbox feature, not available with Sysbox.

**Solution:**

Use ECI mode (Docker Desktop) for credential sharing, or manage credentials manually in Sysbox mode:
```bash
# Use cai import to copy credentials to the volume
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
docker pull eeacms/rsync

# Check volume status
docker volume inspect sandbox-agent-data
```

**Solution:**

1. Ensure Docker daemon is running
2. Pull the rsync image:
   ```bash
   docker pull eeacms/rsync
   ```
3. Check disk space: `docker system df`

### "Source not found, skipping"

**Symptom:**
```
[WARN] Source not found, skipping: /source/.claude.json
```

**Cause:** The source file doesn't exist on your host.

**Solution:**

This is often normal for first-time setup. Run the agent once to create initial files:
```bash
claude  # Run Claude on host first to create config files
cai import  # Then import to volume
```

### "jq transformation failed"

**Symptom:**
```
[ERROR] jq transformation failed for installed_plugins.json
```

**Diagnosis:**
```bash
# Validate the source file
jq '.' ~/.claude/plugins/installed_plugins.json
```

**Solution:**

If the file is corrupted, remove and reimport:
```bash
rm ~/.claude/plugins/installed_plugins.json
cai import
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
3. **Use Docker Desktop ECI** instead of Sysbox (recommended for WSL2)

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

Or explicitly specify context:
```bash
cai run  # Uses auto-selection
# or
CONTAINAI_SECURE_ENGINE_CONTEXT=containai-secure cai run
```

### macOS: "ECI not available"

**Symptom:**
```
ECI (Enhanced Container Isolation): not available    [WARN]
```

**Cause:** Docker Desktop for macOS may require Business subscription for ECI.

**Solution:**

1. **Check subscription**: ECI requires Docker Business
2. **Use Lima with Sysbox** as alternative:
   ```bash
   brew install lima
   limactl start --name=containai-secure template://docker-sysbox
   ```

### macOS: Missing Alpine image

**Symptom:**
```
[ERROR] Image not found: alpine:3.20
Pull alpine:3.20: docker pull alpine:3.20
```

**Cause:** ECI detection requires the Alpine image for uid_map checks.

**Solution:**
```bash
docker pull alpine:3.20
```

### Linux: Permission denied

**Symptom:**
```
[ERROR] Permission denied accessing Docker
```

**Solution:**

Add user to docker group:
```bash
sudo usermod -aG docker $USER
newgrp docker  # Apply immediately
# or log out and back in
```

---

## Security-Related Issues

### "--mount-docker-socket requires acknowledgement"

**Symptom:**
```
[ERROR] --mount-docker-socket requires --please-root-my-host acknowledgement
```

**Cause:** Docker socket mounting is extremely dangerous.

**Solution:**

Only if you understand the risks:
```bash
cai run --mount-docker-socket --please-root-my-host
```

Or use the new explicit flags:
```bash
cai run --allow-host-docker-socket --i-understand-this-grants-root-access
```

**WARNING:** This grants FULL ROOT ACCESS to your host. Avoid unless absolutely necessary.

### "No isolation available"

**Symptom:**
```
Status:                                  [ERROR] No isolation available
Recommended: Install Docker Desktop 4.50+ with ECI, or run 'cai setup'
```

**Cause:** Neither Docker Desktop sandboxes nor Sysbox are available.

**Solution:**

Option 1 (Recommended): Install/update Docker Desktop 4.50+
- https://www.docker.com/products/docker-desktop/
- Enable ECI in Settings > Security

Option 2: Set up Sysbox:
```bash
cai setup
```

Option 3 (Not recommended): Force run without isolation:
```bash
cai run --force
```

### "Container isolation required but not detected"

**Symptom:**
```
[ERROR] Container isolation required but not detected. Use --force to bypass.
```

**Cause:** `CONTAINAI_REQUIRE_ISOLATION=1` is set but isolation isn't available.

**Solution:**

1. Run `cai doctor` to diagnose
2. Fix the underlying isolation issue
3. Or bypass (not recommended):
   ```bash
   CONTAINAI_REQUIRE_ISOLATION=0 cai run
   ```

---

## Startup/Entrypoint Issues

### "Could not discover mirrored workspace mount"

**Symptom:**
```
ERROR: Could not discover mirrored workspace mount via findmnt.
Diagnostics:
{...findmnt output...}
```

**Cause:** Docker sandbox didn't properly mount the workspace.

**Solution:**

1. Ensure workspace path exists on host
2. Restart Docker Desktop
3. Recreate the container:
   ```bash
   cai run --restart
   ```

### "Refusing suspicious workspace candidate"

**Symptom:**
```
ERROR: Refusing suspicious workspace candidate: /etc
```

**Cause:** Workspace resolved to a system directory.

**Solution:**

Specify a valid workspace:
```bash
cai run --workspace ~/projects/myproject
```

### "Workspace is a mountpoint"

**Symptom:**
```
ERROR: /home/agent/workspace is a mountpoint. Refusing to delete.
```

**Cause:** Internal container error during workspace setup.

**Solution:**

Remove and recreate the container:
```bash
docker rm -f <container-name>
cai run
```

### "Path escapes data directory"

**Symptom:**
```
ERROR: Path escapes data directory: /mnt/agent-data/../../../etc/passwd -> /etc/passwd
```

**Cause:** Symlink traversal attack detected in the data volume.

**Solution:**

This is a security protection. The data volume contains a symlink trying to escape. Inspect and fix:
```bash
docker run --rm -it -v sandbox-agent-data:/data alpine sh
# Inside container: find /data -type l -ls
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
echo "cai version: $(cai --version 2>/dev/null || echo 'unknown')" >> versions.txt
```

### 2. Check GitHub Issues

Search existing issues for your error message:
https://github.com/novotny/ContainAI/issues

### 3. Open a New Issue

If your issue isn't documented, open a GitHub issue with:

1. **Error message** (exact text)
2. **Doctor output** (`cai doctor`)
3. **Steps to reproduce**
4. **Platform** (macOS/Linux/WSL2)
5. **Docker version** (`docker version`)

### 4. Community Support

- **GitHub Discussions**: For questions and community help
- **Pull Requests**: Contributions welcome!

---

## Appendix: Error Message Reference

Quick reference of error messages and their section in this guide:

| Error Message | Section |
|---------------|---------|
| "Docker is not installed" | [Installation Issues](#installation-issues) |
| "Docker Desktop is not running" | [Docker Desktop Issues](#docker-desktop-issues) |
| "Docker Desktop 4.50+ required" | [Docker Desktop Issues](#docker-desktop-issues) |
| "docker sandbox command not found" | [Docker Desktop Issues](#docker-desktop-issues) |
| "Sandboxes disabled by administrator" | [Docker Desktop Issues](#docker-desktop-issues) |
| "containai-secure context not found" | [Sysbox Issues](#sysboxsecure-engine-issues) |
| "Sysbox runtime not found" | [Sysbox Issues](#sysboxsecure-engine-issues) |
| "Image not found" | [Container Issues](#container-issues) |
| "Container exists but was not created by ContainAI" | [Container Issues](#container-issues) |
| "Image mismatch" | [Container Issues](#container-issues) |
| "Volume mismatch" | [Container Issues](#container-issues) |
| "Config file not found" | [Configuration Issues](#configuration-issues) |
| "Failed to parse config file" | [Configuration Issues](#configuration-issues) |
| "--credentials=host requires acknowledgement" | [Credential Issues](#credentialimport-issues) |
| "Rsync sync failed" | [Credential Issues](#credentialimport-issues) |
| "Seccomp compatibility: warning" | [WSL2 Issues](#platform-specific-issues) |
| "Permission denied" | [Linux Issues](#platform-specific-issues) |
| "No isolation available" | [Security Issues](#security-related-issues) |
| "Path escapes data directory" | [Startup Issues](#startupentrypoint-issues) |
