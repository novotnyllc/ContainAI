# fn-5-urz.11 macOS Lima VM Secure Engine provisioning

## Description
## Overview

Implement `cai setup` for macOS using Lima VM with Sysbox.

**CRITICAL: NEVER interfere with Docker Desktop** - Docker Desktop must remain the default and unchanged.

## Command

```bash
cai setup [--force] [--dry-run] [--verbose]
```

## What It Does

1. **Detect macOS environment**
   ```bash
   if [[ "$(uname -s)" == "Darwin" ]]; then
       platform="macos"
   fi
   ```

2. **Check Lima installation**
   ```bash
   if ! command -v limactl >/dev/null 2>&1; then
       echo "[INFO] Lima not found. Installing via Homebrew..."
       brew install lima
   fi
   ```

3. **Create Lima VM with Docker + Sysbox**
   - Use Ubuntu 24.04 base image
   - Install Docker Engine inside VM
   - Install Sysbox inside VM
   - Configure daemon.json with sysbox-runc runtime
   - Expose Docker socket to macOS host

4. **Create Docker context**
   ```bash
   docker context create containai-secure \
     --docker "host=unix://$HOME/.lima/containai-secure/sock/docker.sock"
   ```

5. **Docker Desktop Protection**
   - NEVER modify Docker Desktop settings
   - NEVER change the default context
   - NEVER touch `~/.docker/daemon.json` on macOS
   - All operations use explicit `containai-secure` context

## Lima VM Template

```yaml
# ~/.lima/containai-secure/lima.yaml
images:
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    arch: "x86_64"
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"

mounts:
  - location: "~"
    writable: true
  - location: "/tmp/lima"
    writable: true

provision:
  - mode: system
    script: |
      #!/bin/bash
      set -eux

      # Install Docker
      curl -fsSL https://get.docker.com | sh
      usermod -aG docker "${LIMA_CIDATA_USER}"

      # Install Sysbox (x86_64 or arm64)
      ARCH=$(dpkg --print-architecture)
      wget -O /tmp/sysbox.deb "https://downloads.nestybox.com/sysbox/releases/v0.6.7/sysbox-ce_0.6.7-0.linux_${ARCH}.deb"
      apt-get install -y /tmp/sysbox.deb

      # Configure Docker with Sysbox runtime (NOT as default)
      cat > /etc/docker/daemon.json << 'EOF'
      {
        "runtimes": {
          "sysbox-runc": {
            "path": "/usr/bin/sysbox-runc"
          }
        }
      }
      EOF

      systemctl restart docker

portForwards:
  - guestSocket: "/var/run/docker.sock"
    hostSocket: "{{.Dir}}/sock/docker.sock"
```

## ARM64 (Apple Silicon) Handling

Sysbox supports ARM64 natively. The Lima template uses architecture-specific images:
- x86_64: Standard AMD64 image
- aarch64: ARM64 image (Apple Silicon)

## Context Creation

```bash
docker context create containai-secure \
  --docker "host=unix://$HOME/.lima/containai-secure/sock/docker.sock"
```

## Verification

```bash
# Verify Lima VM is running
limactl list

# Verify Sysbox is available via containai-secure context
docker --context containai-secure info | grep -i sysbox

# Verify Docker Desktop is still default
docker context ls  # default or desktop-linux should be active
```

## Depends On

<!-- Updated by plan-sync: fn-5-urz.1 Sysbox context confirmed, sandbox context UNKNOWN (blocked) -->
- Task 1 spike (fn-5-urz.1) findings:
  - **Sysbox context: CONFIRMED** - Proceeds with Sysbox setup in Lima VM
  - **Sandbox context: UNKNOWN** - Blocked pending Docker Desktop 4.50+ testing
- NOTE: Spike document recommends NOT proceeding until Docker Desktop testing completes

## References

- Lima: https://github.com/lima-vm/lima
- Lima Docker example: https://lima-vm.io/docs/examples/containers/docker/
- Sysbox ARM64: https://github.com/nestybox/sysbox/releases
## Overview

Implement `containai install secure-engine` for macOS using Lima VM.

## Approach

Docker Sandboxes requires Docker Desktop for the `docker sandbox` CLI plugin. The Secure Engine provides additional isolation via a Lima VM running:
- Docker Engine with Sysbox
- User namespace remapping
- Optional seccomp profile

## What It Does

1. Check Lima is installed (or install via Homebrew)
2. Create Lima VM with Docker + Sysbox configuration
3. Configure daemon.json in VM
4. Expose Docker socket to macOS host
5. Create Docker context `containai-secure`

## Lima VM Template

```yaml
# containai-secure.yaml
images:
  - location: "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
    arch: "x86_64"

mounts:
  - location: "~"
    writable: true

provision:
  - mode: system
    script: |
      # Install Docker
      curl -fsSL https://get.docker.com | sh

      # Install Sysbox (x86_64 only for now)
      # ... sysbox installation

      # Configure daemon
      cat > /etc/docker/daemon.json << 'EOF'
      {
        "default-runtime": "sysbox-runc",
        "userns-remap": "default"
      }
      EOF

      systemctl restart docker
```

## ARM64 (Apple Silicon) Consideration

Sysbox is primarily x86_64. ARM64 support is limited. Options:
1. Use Rosetta 2 emulation in Lima
2. Fall back to userns-remap only (no Sysbox)
3. Document as x86_64 only

## Context Creation

```bash
docker context create containai-secure \
  --docker "host=unix://$HOME/.lima/containai-secure/sock/docker.sock"
```

## References

- Lima: https://github.com/lima-vm/lima
- Lima Docker example: https://lima-vm.io/docs/examples/containers/docker/
## Acceptance
- [ ] Detects macOS environment correctly
- [ ] Installs Lima via Homebrew if not present (or prompts)
- [ ] Creates Lima VM named `containai-secure`
- [ ] Lima VM has Docker + Sysbox installed
- [ ] Sysbox is NOT set as default runtime in VM
- [ ] Creates `containai-secure` Docker context
- [ ] Socket path is correct for Lima (`~/.lima/containai-secure/sock/docker.sock`)
- [ ] Works on both Intel and Apple Silicon Macs
- [ ] Does NOT interfere with Docker Desktop
- [ ] Does NOT modify default or desktop-linux context
- [ ] Docker Desktop remains the active/default context after setup
- [ ] VM can be started/stopped via `limactl start/stop containai-secure`
- [ ] `--dry-run` shows what would be done without changes
## Done summary
Implemented macOS Lima VM Secure Engine provisioning for `cai setup`. Creates a Lima VM with Docker Engine + Sysbox, exposes Docker socket to macOS host, and creates `containai-secure` Docker context. Supports both Intel and Apple Silicon Macs. Does NOT interfere with Docker Desktop (remains default context).
## Evidence
- Commits: 24d4724, 2b45c64
- Tests: bash -n agent-sandbox/lib/setup.sh, shellcheck -x agent-sandbox/lib/setup.sh
- PRs:
