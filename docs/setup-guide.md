# ContainAI Setup Guide

This guide covers the complete installation and configuration of ContainAI across all supported platforms. ContainAI provides isolated sandbox environments for AI coding agents using Sysbox system containers.

## Table of Contents

- [Prerequisites](#prerequisites)
- [What Gets Installed](#what-gets-installed)
- [Platform-Specific Setup](#platform-specific-setup)
  - [WSL2 (Windows)](#wsl2-windows)
  - [Native Linux](#native-linux)
  - [macOS (via Lima)](#macos-via-lima)
- [CLI Output Behavior](#cli-output-behavior)
- [Component Details](#component-details)
- [Verification](#verification)
- [Troubleshooting Setup](#troubleshooting-setup)
- [Updating ContainAI](#updating-containai)
- [Uninstalling](#uninstalling)

---

## Prerequisites

Before running `cai setup`, ensure you have:

### All Platforms

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| Bash | 4.0+ | `bash --version` |
| Docker CLI | Any recent | `docker --version` |
| jq | Any | `jq --version` |
| ripgrep (rg) | Any | `rg --version` |
| OpenSSH client | 7.3+ | `ssh -V` |

**Note on Docker:** Only the Docker CLI is required. On Linux/WSL2, ContainAI installs and manages its own dockerd bundle - you do not need Docker Engine or Docker Desktop installed. On macOS, ContainAI uses a Lima VM.

### WSL2 (Windows)

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| WSL2 kernel | 5.5+ | `uname -r` |
| systemd | Enabled | `ps -p 1 -o comm=` (should show `systemd`) |
| Ubuntu/Debian | 22.04+ / 11+ | `lsb_release -a` |

**Enable systemd in WSL2** (if not already enabled):

```bash
# Add to /etc/wsl.conf
sudo tee /etc/wsl.conf << 'EOF'
[boot]
systemd=true
EOF
```

Then restart WSL from PowerShell:

```powershell
wsl --shutdown
```

### Native Linux

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| Kernel | 5.5+ | `uname -r` |
| systemd | Running | `systemctl --version` |
| Ubuntu/Debian | 22.04+ / 11+ | For auto-install; manual install for others |

### macOS

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| macOS | 12+ | `sw_vers` |
| Homebrew | Any | `brew --version` |
| Lima | Installed by setup | `limactl --version` |

---

## What Gets Installed

The `cai setup` command installs and configures multiple components. Here's what gets installed on each platform:

### Installation Summary

```
+------------------------------------------------------------------+
|                    ContainAI Installation                         |
+------------------------------------------------------------------+
|                                                                    |
|  Host System                                                       |
|  +------------------------------------------------------------+   |
|  |                                                             |   |
|  |  Docker Configuration (WSL2/Linux only)                    |   |
|  |  +---------------------------------------------------------+|   |
|  |  | - Socket: /var/run/containai-docker.sock (isolated)     ||   |
|  |  | - Config: /etc/containai/docker/daemon.json             ||   |
|  |  | - Service: containai-docker.service (dedicated)         ||   |
|  |  | - Runtime: sysbox-runc (default for isolated daemon)    ||   |
|  |  +---------------------------------------------------------+|   |
|  |                                                             |   |
|  |  Sysbox Runtime                                             |   |
|  |  +---------------------------------------------------------+|   |
|  |  | - sysbox-runc: Container runtime with userns isolation  ||   |
|  |  | - sysbox-mgr: Manager service                           ||   |
|  |  | - sysbox-fs: Filesystem virtualization                  ||   |
|  |  +---------------------------------------------------------+|   |
|  |                                                             |   |
|  |  Docker Context                                             |   |
|  |  +---------------------------------------------------------+|   |
|  |  | - Name: containai-docker                                ||   |
|  |  | - Points to: appropriate socket for platform            ||   |
|  |  +---------------------------------------------------------+|   |
|  |                                                             |   |
|  |  SSH Infrastructure                                         |   |
|  |  +---------------------------------------------------------+|   |
|  |  | - Key: ~/.config/containai/id_containai (ed25519)       ||   |
|  |  | - Config dir: ~/.ssh/containai.d/                       ||   |
|  |  | - Include in: ~/.ssh/config                             ||   |
|  |  | - Known hosts: ~/.config/containai/known_hosts          ||   |
|  |  +---------------------------------------------------------+|   |
|  |                                                             |   |
|  |  User Configuration                                         |   |
|  |  +---------------------------------------------------------+|   |
|  |  | - Config: ~/.config/containai/config.toml               ||   |
|  |  +---------------------------------------------------------+|   |
|  |                                                             |   |
|  +------------------------------------------------------------+   |
+------------------------------------------------------------------+
```

### Platform Comparison

| Component | WSL2 | Native Linux | macOS |
|-----------|------|--------------|-------|
| Docker daemon | Isolated `containai-docker.service` | Isolated `containai-docker.service` | Lima VM |
| Docker socket | `/var/run/containai-docker.sock` | `/var/run/containai-docker.sock` | `~/.lima/containai-docker/sock/docker.sock` |
| Docker config | `/etc/containai/docker/daemon.json` | `/etc/containai/docker/daemon.json` | Inside Lima VM |
| Sysbox install | GitHub releases (Ubuntu/Debian) | GitHub releases (Ubuntu/Debian) | Inside Lima VM |
| Sysbox services | systemd | systemd | Lima VM systemd |
| Context name | `containai-docker` | `containai-docker` | `containai-docker` |

---

## ContainAI-managed dockerd bundle

On Linux and WSL2, ContainAI installs and manages its own Docker daemon bundle. This ensures consistent behavior across installations and enables atomic updates.

### How it works

- **Installed automatically**: The dockerd bundle is installed during `cai setup` on Linux/WSL2
- **No system Docker required**: You do not need Docker Engine or Docker Desktop installed on your system
- **Versioned structure**: Binaries are installed to `/opt/containai/docker/<version>/`
- **Stable symlinks**: The systemd service uses `/opt/containai/bin/` symlinks
- **Atomic updates**: Updates swap symlinks atomically via `cai update`

### Directory structure

```
/opt/containai/
├── docker/
│   ├── 27.3.1/              # Previous version (kept for rollback)
│   │   ├── dockerd
│   │   ├── docker
│   │   ├── containerd
│   │   └── ...
│   └── 27.4.0/              # Current version
│       ├── dockerd
│       ├── docker
│       ├── containerd
│       └── ...
├── bin/                     # Stable symlinks (systemd uses these)
│   ├── dockerd -> ../docker/27.4.0/dockerd
│   ├── docker -> ../docker/27.4.0/docker
│   └── ...
└── VERSION                  # Contains current version string
```

### Updating the bundle

To check for and apply updates:

```bash
cai update
```

Updates are applied atomically by swapping symlinks and restarting the `containai-docker` service.

**Note:** On macOS, ContainAI uses a Lima VM with its own Docker installation. The dockerd bundle is not used on macOS.

---

## Platform-Specific Setup

### WSL2 (Windows)

ContainAI installs and manages its own dockerd bundle on WSL2 - you do not need Docker Engine or Docker Desktop installed. The setup creates a completely isolated Docker daemon. Note that Docker Desktop integration mode is not supported (Sysbox requires a native Linux Docker daemon).

#### What WSL2 Setup Does

1. **Checks kernel version** (requires 5.5+)
2. **Tests seccomp compatibility** (WSL 1.1.0+ may have conflicts)
3. **Downloads and installs Sysbox** from GitHub releases (Ubuntu/Debian)
4. **Downloads and installs dockerd bundle** to `/opt/containai/docker/<version>/`
5. **Creates isolated daemon config** at `/etc/containai/docker/daemon.json`
6. **Creates dedicated systemd service** `containai-docker.service`
7. **Starts isolated Docker daemon** at `/var/run/containai-docker.sock`
8. **Creates Docker context** `containai-docker`
9. **Sets up SSH infrastructure**

**Note:** Your system Docker at `/var/run/docker.sock` is never touched (if present).

#### Run Setup

```bash
# Source ContainAI CLI
source /path/to/containai/src/containai.sh

# Run setup (silent by default)
cai setup

# Or with verbose output to see progress messages
cai setup --verbose

# If seccomp warning appears, use --force
cai setup --force
```

> **Note:** Commands are silent by default (Unix Rule of Silence). Use `--verbose` to see status messages during setup, or set `CONTAINAI_VERBOSE=1` for persistent verbosity. Warnings and errors always emit to stderr regardless of verbosity settings.

#### WSL2 Component Locations

| Component | Path |
|-----------|------|
| Docker daemon config | `/etc/containai/docker/daemon.json` |
| Docker socket | `/var/run/containai-docker.sock` |
| Systemd service | `/etc/systemd/system/containai-docker.service` |
| Sysbox binaries | `/usr/bin/sysbox-runc`, `/usr/bin/sysbox-mgr`, `/usr/bin/sysbox-fs` |
| SSH key | `~/.config/containai/id_containai` |
| SSH config dir | `~/.ssh/containai.d/` |
| User config | `~/.config/containai/config.toml` |
| Known hosts | `~/.config/containai/known_hosts` |

#### WSL2 Docker Configuration

The setup creates an **isolated Docker daemon** that never touches system Docker. The configuration is stored at `/etc/containai/docker/daemon.json`:

```json
{
  "default-runtime": "sysbox-runc",
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  },
  "hosts": ["unix:///var/run/containai-docker.sock"],
  "data-root": "/var/lib/containai-docker",
  "exec-root": "/var/run/containai-docker",
  "pidfile": "/var/run/containai-docker.pid",
  "bridge": "cai0"
}
```

During setup, the `cai0` bridge is created and assigned `172.30.0.1/16` to avoid
subnet conflicts with system Docker.

The systemd service `/etc/systemd/system/containai-docker.service` runs a dedicated Docker daemon:

```ini
[Unit]
Description=ContainAI Docker Daemon (isolated)
After=network.target containerd.service sysbox.service

[Service]
ExecStart=/opt/containai/bin/dockerd --config-file=/etc/containai/docker/daemon.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

#### Windows Docker CLI (named pipe)

ContainAI can expose the isolated daemon to Windows via a named pipe. If `npiperelay.exe` is available in the Windows PATH, `cai setup` will:

If `npiperelay.exe` is missing, `cai setup` attempts to install it via `winget.exe install jstarks.npiperelay`.

1. Install `socat` in WSL (if needed)
2. Create and start the systemd service `containai-npipe-bridge.service`
3. Configure the Windows Docker context `containai-docker` to use the named pipe:

```powershell
docker --context containai-docker info
```

The named pipe endpoint is `npipe:////./pipe/containai-docker`.

---

### Native Linux

ContainAI installs and manages its own dockerd bundle on Linux - you do not need Docker Engine installed. The setup creates a completely **isolated Docker daemon** that never touches your system Docker installation (if present).

#### What Native Linux Setup Does

1. **Checks kernel version** (requires 5.5+)
2. **Downloads and installs Sysbox** from GitHub releases (Ubuntu/Debian only)
3. **Downloads and installs dockerd bundle** to `/opt/containai/docker/<version>/`
4. **Creates isolated daemon config** at `/etc/containai/docker/daemon.json`
5. **Creates dedicated systemd service** `containai-docker.service`
6. **Creates Docker context** `containai-docker` pointing to isolated socket
7. **Sets up SSH infrastructure**

**Note:** Your system Docker at `/var/run/docker.sock` and `/etc/docker/` is never touched (if present).

#### Run Setup

```bash
# Source ContainAI CLI
source /path/to/containai/src/containai.sh

# Run setup (silent by default)
cai setup

# Or with verbose output to see progress messages
cai setup --verbose
```

#### Manual Sysbox Installation (Non-Ubuntu/Debian)

For distributions other than Ubuntu/Debian, install Sysbox manually following the [official Sysbox installation guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md).

```bash
# Download the appropriate package from GitHub releases:
# https://github.com/nestybox/sysbox/releases

# Install the downloaded package for your distribution

# Then run setup to configure Docker
cai setup
```

#### Native Linux Component Locations

| Component | Path |
|-----------|------|
| Docker daemon config | `/etc/containai/docker/daemon.json` |
| Docker socket | `/var/run/containai-docker.sock` |
| Systemd service | `/etc/systemd/system/containai-docker.service` |
| Sysbox binaries | `/usr/bin/sysbox-runc`, `/usr/bin/sysbox-mgr`, `/usr/bin/sysbox-fs` |
| SSH key | `~/.config/containai/id_containai` |
| SSH config dir | `~/.ssh/containai.d/` |
| User config | `~/.config/containai/config.toml` |
| Known hosts | `~/.config/containai/known_hosts` |

---

### macOS (via Lima)

macOS uses Lima to run a Linux VM with Docker and Sysbox. This provides the same isolation as native Linux.

#### What macOS Setup Does

1. **Installs Lima** via Homebrew (if not present)
2. **Creates Lima VM** `containai-docker` with:
   - Ubuntu 24.04 LTS
   - Docker Engine
   - Sysbox runtime
3. **Waits for Docker socket** to be ready
4. **Creates Docker context** `containai-docker` pointing to Lima socket
5. **Sets up SSH infrastructure**

#### Run Setup

```bash
# Source ContainAI CLI
source /path/to/containai/src/containai.sh

# Run setup (silent by default; may take several minutes for Lima VM creation)
cai setup

# Or with verbose output to see progress messages
cai setup --verbose
```

#### macOS Component Locations

| Component | Path |
|-----------|------|
| Lima VM | `~/.lima/containai-docker/` |
| Docker socket (via Lima) | `~/.lima/containai-docker/sock/docker.sock` |
| Lima VM config | `~/.lima/containai-docker/lima.yaml` |
| SSH key | `~/.config/containai/id_containai` |
| SSH config dir | `~/.ssh/containai.d/` |
| User config | `~/.config/containai/config.toml` |
| Known hosts | `~/.config/containai/known_hosts` |

#### Managing the Lima VM

```bash
# Check Lima VM status
limactl list

# Start the VM (if stopped)
limactl start containai-docker

# Stop the VM
limactl stop containai-docker

# Shell into the VM
limactl shell containai-docker

# Delete the VM (removes all data inside VM)
limactl delete containai-docker
```

---

## CLI Output Behavior

ContainAI follows the Unix "Rule of Silence" - commands are silent by default and only produce output when there's something meaningful to report.

### Default Behavior

- **Silent by default**: Info and status messages are suppressed
- **Warnings and errors always emit**: Important messages always go to stderr
- **Piping-friendly**: Silent default allows clean piping and scripting

### Enabling Verbose Output

Use the `--verbose` flag (long form only) to see status messages:

```bash
# See progress during setup
cai setup --verbose

# See connection messages during shell
cai shell --verbose

# Verbose import
cai import --verbose
```

Or set the environment variable for persistent verbosity:

```bash
# Enable for current session
export CONTAINAI_VERBOSE=1
cai setup

# Or per-command
CONTAINAI_VERBOSE=1 cai shell
```

### Precedence Rules

When multiple verbosity controls are specified:

1. `--quiet` overrides everything (suppresses info/step/ok messages)
2. `--verbose` takes next priority (enables info/step/ok messages)
3. `CONTAINAI_VERBOSE=1` env var is the default fallback

Example:

```bash
# Quiet wins over env var
CONTAINAI_VERBOSE=1 cai shell --quiet  # Silent

# --verbose enables output
cai setup --verbose  # Shows progress
```

### Note on `-v` Flag

The `-v` short flag is **not** a verbose shorthand. This avoids conflicts with:
- Top-level `cai -v` for `--version`
- Docker conventions where `-v` means volume mount

Always use `--verbose` (long form) for verbosity.

---

## Component Details

### Docker Context: containai-docker

The `containai-docker` Docker context points to the Sysbox-enabled Docker daemon:

```bash
# List contexts
docker context ls

# Use the context explicitly
docker --context containai-docker info

# Check runtime configuration
docker --context containai-docker info | grep -A5 Runtimes
```

Expected output shows `sysbox-runc` in the runtimes list.

### SSH Infrastructure

ContainAI generates a dedicated SSH key for container access:

```bash
# View the public key
cat ~/.config/containai/id_containai.pub

# Check SSH config directory
ls -la ~/.ssh/containai.d/

# Verify Include directive in ~/.ssh/config
grep -i "containai" ~/.ssh/config
```

The Include directive in `~/.ssh/config` should look like:

```
Include ~/.ssh/containai.d/*.conf
```

### Sysbox Services

On Linux/WSL2, Sysbox runs as systemd services:

```bash
# Check Sysbox services
systemctl status sysbox-mgr
systemctl status sysbox-fs

# View Sysbox version
sysbox-runc --version
```

---

## Verification

After setup, verify the installation with `cai doctor`:

```bash
cai doctor
```

### Expected Output

The output varies by platform, but key sections to look for:

```
ContainAI Doctor
================

Docker
  Docker CLI:                                [OK]
  Docker daemon:                             [OK]

Sysbox Isolation
  Sysbox available:                          [OK]
  Runtime: sysbox-runc                       [OK]
  Context 'containai-docker':                [OK] Configured

Platform: WSL2
  Kernel version: 5.15                       [OK]
  Seccomp compatibility: ok                  [OK]

SSH
  SSH key exists:                            [OK]
  SSH config directory:                      [OK]
  Include directive:                         [OK]
  OpenSSH version:                           [OK] 8.9
```

### Doctor Output Interpretation

| Status | Meaning |
|--------|---------|
| `[OK]` | Component working correctly |
| `[WARN]` | Minor issue, may still work |
| `[ERROR]` | Blocking issue, needs attention |
| `[INFO]` | Informational note |
| `[SKIP]` | Check skipped due to earlier failure |

### Manual Verification Commands

```bash
# Verify Docker context works
docker --context containai-docker info

# Verify Sysbox runtime is available
docker --context containai-docker info | grep sysbox

# Test a Sysbox container
docker --context containai-docker run --rm --runtime=sysbox-runc alpine echo "Sysbox works!"

# Verify SSH key exists and has correct permissions
ls -la ~/.config/containai/id_containai
# Should show: -rw------- (600)

# Verify SSH config directory exists
ls -la ~/.ssh/containai.d/
# Should show: drwx------ (700)

# Verify Include directive
grep -i "include.*containai" ~/.ssh/config
```

---

## Troubleshooting Setup

### WSL2: Seccomp Warning

**Symptom:**
```
+==================================================================+
|                       *** WARNING ***                            |
+==================================================================+
| Sysbox on WSL2 may not work due to seccomp filter conflicts.    |
```

**Solution:**

1. **Proceed anyway** (Sysbox often works despite the warning):
   ```bash
   cai setup --force
   ```

2. **Downgrade WSL** to avoid seccomp conflicts:
   ```powershell
   wsl --update --web-download --version 1.0.3
   ```

### WSL2: Systemd Not Running

**Symptom:**
```
[ERROR] Systemd is not running as PID 1 (found: init)
```

**Solution:**

Enable systemd in WSL:

```bash
# Edit /etc/wsl.conf
sudo tee /etc/wsl.conf << 'EOF'
[boot]
systemd=true
EOF
```

Then restart WSL from PowerShell:

```powershell
wsl --shutdown
```

### Docker Socket Permission Denied

**Symptom:**
```
[ERROR] Permission denied accessing Docker
```

**Solution:**

Add your user to the docker group:

```bash
sudo usermod -aG docker $USER
newgrp docker  # Apply immediately without logout
```

### Sysbox Installation Failed

**Symptom:**
```
[ERROR] Sysbox auto-install only supports Ubuntu/Debian
```

**Solution:**

Install Sysbox manually for your distribution. See the [Sysbox installation guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md).

### macOS: Lima VM Creation Failed

**Symptom:**
```
[ERROR] Failed to create Lima VM
```

**Solution:**

1. Check Homebrew is installed:
   ```bash
   brew --version
   ```

2. Install Lima manually:
   ```bash
   brew install lima
   ```

3. Try creating the VM manually:
   ```bash
   limactl create --name=containai-docker
   limactl start containai-docker
   ```

### macOS: Docker Permission Denied in Lima

**Symptom:**
Socket exists but `docker info` fails with permission denied.

**Solution:**

The setup should auto-repair this. If not, manually add user to docker group:

```bash
limactl shell containai-docker sudo usermod -aG docker $USER
limactl stop containai-docker
limactl start containai-docker
```

### General: Kernel Too Old

**Symptom:**
```
[ERROR] Kernel 5.4.0 is too old. Sysbox requires kernel 5.5+
```

**Solution:**

- **WSL2**: Update WSL kernel:
  ```powershell
  wsl --update
  wsl --shutdown
  ```

- **Linux**: Update your distribution or kernel.

---

## Updating ContainAI

Use `cai update` to apply updates to your ContainAI installation. The update process differs by platform and handles multiple components.

### What Gets Updated

| Component | WSL2/Linux | macOS |
|-----------|------------|-------|
| dockerd bundle | Atomic symlink swap | N/A (Lima VM) |
| Sysbox runtime | Package upgrade | VM package update |
| Systemd unit | Template reconciliation | N/A |
| Docker context | Socket path update | Socket path update |
| Lima VM packages | N/A | apt-get upgrade |

### Basic Update Flow

```bash
# Preview what would be updated (no changes made)
cai update --dry-run

# Apply updates
cai update
```

### Container Safety

Updates to the dockerd bundle, sysbox, or systemd unit require restarting the containai-docker service. This stops all running ContainAI containers.

**Default behavior when updates are pending and containers are running:**
- `cai update` aborts with an actionable message listing the running containers
- You must explicitly acknowledge container stoppage

```bash
# List running containers before update
docker --context containai-docker ps

# Proceed with container stop
cai update --stop-containers
```

### Update Command Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Preview changes without making any modifications |
| `--stop-containers` | Stop running containers before applying updates (Linux/WSL2) |
| `--force` | Skip confirmation prompts (e.g., VM recreation on macOS) |
| `--lima-recreate` | Delete and recreate Lima VM instead of in-place update (macOS only) |

### Platform-Specific Behavior

**WSL2 / Native Linux:**
1. Checks for running containers; aborts if found (unless `--stop-containers`)
2. Updates systemd unit template if changed
3. Updates Docker context if socket path changed
4. Updates dockerd bundle if newer version available
5. Updates sysbox if newer version available
6. Restarts containai-docker service (when updates applied)

**macOS (Lima):**
1. Updates Lima VM packages via `apt-get upgrade`
2. Updates sysbox inside the VM if newer version available
3. Checks if Lima template changed (hash mismatch or first update)
   - If changed: prompts to recreate VM (containers will be lost)
   - `--lima-recreate` forces recreation regardless of template
   - `--force` auto-confirms recreation prompts
4. Updates Docker context if socket path changed

**Note:** VM recreation is destructive - all containers inside the Lima VM are lost. Data in persistent volumes outside the VM is preserved.

### Version Detection

ContainAI checks for updates by comparing:
- **dockerd bundle**: Local version in `/opt/containai/VERSION` vs latest from download.docker.com
- **Sysbox**: Local `sysbox-runc --version` vs latest from GitHub releases
- **Systemd unit**: Local unit content vs expected template

On macOS, sysbox version is queried inside the Lima VM via `limactl shell`.

### Disabling Update Checks

The automatic update check runs before most `cai` commands (skipped for `--help`, `--version`, and in CI environments). To disable:

```bash
# Disable for current session (works with any cai command)
CAI_UPDATE_CHECK_INTERVAL=never cai <command>

# Disable permanently in config
# Add to ~/.config/containai/config.toml:
[update]
check_interval = "never"
```

---

## Uninstalling

To remove ContainAI components, follow the manual cleanup steps below for your platform.

### Remove Docker Context

```bash
docker context rm containai-docker
```

### WSL2/Linux - Remove Isolated Docker Service

```bash
sudo systemctl stop containai-docker
sudo systemctl disable containai-docker
sudo rm -f /etc/systemd/system/containai-docker.service
sudo rm -rf /etc/containai/docker/
sudo rm -rf /var/lib/containai-docker/
sudo rm -f /var/run/containai-docker.sock
sudo systemctl daemon-reload
```

### Remove SSH Configuration

```bash
rm -rf ~/.ssh/containai.d/
rm -f ~/.config/containai/id_containai*
rm -f ~/.config/containai/known_hosts
```

Manually remove the Include line from `~/.ssh/config`:

```bash
# Edit ~/.ssh/config and remove this line:
# Include ~/.ssh/containai.d/*.conf
```

### macOS - Remove Lima VM

```bash
limactl stop containai-docker
limactl delete containai-docker
```

### What is Preserved

The cleanup steps above do not remove:
- `~/.config/containai/config.toml` (user configuration)
- Docker images and volumes (remove with `docker image prune` / `docker volume prune`)
- Sysbox installation (remove with your package manager if desired)

---

## See Also

- [Architecture](architecture.md) - System container architecture and design
- [Configuration](configuration.md) - Configuration file reference
- [Troubleshooting](troubleshooting.md) - Comprehensive troubleshooting guide
- [Security Comparison](security-comparison.md) - How ContainAI compares to alternatives
- [Sysbox Documentation](https://github.com/nestybox/sysbox) - Sysbox runtime documentation
