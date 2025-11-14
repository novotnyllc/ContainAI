# Troubleshooting Guide

This guide helps you diagnose and fix common issues with CodingAgents.

## Table of Contents

- [Prerequisites Issues](#prerequisites-issues)
- [Docker Issues](#docker-issues)
- [Authentication Issues](#authentication-issues)
- [Container Issues](#container-issues)
- [Network Issues](#network-issues)
- [Image Issues](#image-issues)
- [Git Issues](#git-issues)
- [Platform-Specific Issues](#platform-specific-issues)
- [Performance Issues](#performance-issues)
- [Error Reference](#error-reference)

## Prerequisites Issues

### Docker Not Installed

**Symptoms:**
```
bash: docker: command not found
```

**Solution:**
- **Windows/Mac**: Download and install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- **Linux**: Follow [installation guide](https://docs.docker.com/engine/install/)

**Verify:**
```bash
docker --version
```

### Git Not Configured

**Symptoms:**
```
✗ Git user.name not configured
✗ Git user.email not configured
```

**Solution:**
```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

**Verify:**
```bash
git config --global user.name
git config --global user.email
```

### GitHub CLI Not Authenticated

**Symptoms:**
```
✗ GitHub CLI is not authenticated
gh: Not authenticated
```

**Solution:**
```bash
gh auth login
# Follow interactive prompts
```

**Verify:**
```bash
gh auth status
```

**If still fails:**
```bash
# Logout and try again
gh auth logout
gh auth login
```

## Docker Issues

### Docker Daemon Not Running

**Symptoms:**
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
Is the docker daemon running?
```

**Solutions:**

**Windows/Mac:**
1. Open Docker Desktop
2. Wait for whale icon to show "Docker Desktop is running"
3. Try command again

**Linux:**
```bash
# Start Docker service
sudo systemctl start docker

# Enable auto-start on boot
sudo systemctl enable docker

# Check status
sudo systemctl status docker
```

### Permission Denied (Linux)

**Symptoms:**
```
permission denied while trying to connect to the Docker daemon socket
```

**Solution:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in (or restart)
# Verify with:
groups
# Should show: ... docker ...
```

**Temporary workaround** (not recommended for regular use):
```bash
sudo docker <command>
```

### Docker Desktop Not Starting (Windows)

**Symptoms:**
- Docker Desktop stuck on "Starting..."
- WSL integration errors

**Solutions:**

**1. Check WSL2:**
```powershell
# Check WSL version
wsl --version

# If not installed:
wsl --install
# Restart computer
```

**2. Reset Docker Desktop:**
- Right-click Docker Desktop in system tray
- Choose "Quit Docker Desktop"
- Open Task Manager → End any docker processes
- Start Docker Desktop again

**3. Reinstall Docker Desktop:**
- Uninstall Docker Desktop
- Delete `%APPDATA%\Docker`
- Reinstall from [docker.com](https://www.docker.com/products/docker-desktop/)

### Docker Desktop Not Starting (Mac)

**Symptoms:**
- Docker Desktop stuck on "Starting..."
- "Docker failed to initialize" error

**Solutions:**

**1. Reset Docker:**
- Click Docker icon in menu bar
- Troubleshoot → Reset to factory defaults

**2. Check disk space:**
```bash
df -h
# Need at least 5GB free
```

**3. Reinstall Docker Desktop:**
- Remove `/Applications/Docker.app`
- Remove `~/Library/Group Containers/group.com.docker`
- Reinstall from [docker.com](https://www.docker.com/products/docker-desktop/)

## Authentication Issues

### GitHub CLI Token Expired

**Symptoms:**
```
gh: HTTP 401: Bad credentials
✗ GitHub CLI authentication failed
```

**Solution:**
```bash
# Refresh authentication
gh auth refresh

# Or logout and login again
gh auth logout
gh auth login
```

### OAuth Scope Insufficient

**Symptoms:**
```
Error: Insufficient permissions
```

**Solution:**
```bash
# Re-authenticate with required scopes
gh auth login --scopes repo,read:org,user:email
```

### Agent Authentication Not Found

**Symptoms:**
```
❌ Copilot authentication not found
```

**Solution:**

Agents use your host authentication, mounted read-only into containers.

**GitHub Copilot:**
```bash
# On host machine:
gh auth login
gh copilot auth  # If using Copilot CLI
```

**OpenAI Codex:**
```bash
# Set up on host machine
# Store credentials in ~/.config/codex/
```

**Anthropic Claude:**
```bash
# Set up on host machine
# Store credentials in ~/.config/claude/
```

**Verify mount:**
```bash
docker run --rm -v ~/.config/gh:/test:ro alpine ls -la /test
# Should show your gh config files
```

## Container Issues

### Container Exits Immediately

**Symptoms:**
```
Container starts then exits immediately
docker ps shows nothing
```

**Diagnosis:**
```bash
# Check logs
docker logs <container-name>

# Check last 20 lines
docker logs --tail 20 <container-name>
```

**Common Causes:**

**1. Repository path doesn't exist:**
```
Error: /workspace: No such file or directory
```
**Solution:** Verify path exists and is a git repository

**2. Not a git repository:**
```
Error: not a git repository
```
**Solution:** Run from within a git repository or provide correct path

**3. Branch name invalid:**
```
Error: invalid branch name
```
**Solution:** Branch names must match: `[a-zA-Z0-9/_-]+`

### Container Won't Start

**Symptoms:**
```
docker: Error response from daemon: Conflict
```

**Cause:** Container with same name already exists

**Solution:**
```bash
# Check existing containers
docker ps -a | grep <container-name>

# Remove if not needed
docker rm <container-name>

# Or stop and remove
docker stop <container-name>
docker rm <container-name>

# Or force remove
docker rm -f <container-name>
```

### Container Not Accessible

**Symptoms:**
```
Cannot connect to container
docker exec fails
```

**Diagnosis:**
```bash
# Check container is running
docker ps --filter name=<container-name>

# Check container status
docker inspect <container-name> --format='{{.State.Status}}'
```

**Solutions:**

**If stopped:**
```bash
docker start <container-name>
```

**If stuck/unhealthy:**
```bash
docker restart <container-name>
```

**If corrupted:**
```bash
docker rm -f <container-name>
# Launch again with launch-agent or run-* script
```

### Container Uses Wrong Branch

**Symptoms:**
- Working on wrong branch
- Changes go to unexpected branch

**Cause:** Branch isolation not working

**Diagnosis:**
```bash
docker exec <container-name> git branch --show-current
```

**Solution:**
```bash
# Persistent containers: specify branch
launch-agent copilot . -b my-feature

# Ephemeral containers: use current branch
cd /path/to/repo
git checkout my-feature
run-copilot
```

### Cannot Remove Container

**Symptoms:**
```
Error: container is running
Error: unable to remove container
```

**Solutions:**

**Force remove:**
```bash
docker rm -f <container-name>
```

**If still fails:**
```bash
# Stop Docker Desktop (Windows/Mac)
# Or restart Docker daemon (Linux)
sudo systemctl restart docker

# Try again
docker rm -f <container-name>
```

## Network Issues

### Cannot Pull Images

**Symptoms:**
```
Error response from daemon: Get https://registry.docker.com: net/http: TLS handshake timeout
```

**Solutions:**

**1. Check internet connection:**
```bash
ping docker.io
```

**2. Check firewall/proxy:**
- Verify firewall allows Docker
- Configure Docker proxy if behind corporate firewall

**3. Use different registry mirror:**
```bash
# Edit Docker daemon config
# Linux: /etc/docker/daemon.json
# Windows/Mac: Docker Desktop settings

{
  "registry-mirrors": ["https://mirror.gcr.io"]
}

# Restart Docker
```

**4. Manual download:**
If network issues persist, download images on another machine:
```bash
# On machine with internet:
docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest
docker save coding-agents-copilot:latest > copilot.tar

# Transfer copilot.tar to your machine

# On your machine:
docker load < copilot.tar
```

### Container Cannot Reach Internet

**Symptoms:**
```
# Inside container:
curl: (6) Could not resolve host
```

**For network=bridge (default):**

**Linux:**
```bash
# Check Docker network
docker network inspect bridge

# Reset Docker networking
sudo systemctl restart docker
```

**Windows/Mac:**
- Restart Docker Desktop
- Check Docker Desktop → Settings → Resources → Network

**For network=restricted:**

This is expected! Restricted mode (`--network none`) blocks all network access.

**To allow network:**
```bash
# Remove restriction
launch-agent copilot . --network-proxy allow-all
```

**For network=squid:**

Check proxy logs:
```bash
# Find proxy container
docker ps --filter "label=coding-agents.type=proxy"

# Check logs
docker logs <proxy-container-name>
```

### Squid Proxy Blocks Domain

**Symptoms:**
```
# Inside container:
curl: (7) Failed to connect to hostname port 443: Connection refused
```

**Cause:** Domain not in allowed list

**Solution:**

**Option 1: Add domain to allowed list**
Edit `launch-agent` script:
```bash
SQUID_ALLOWED_DOMAINS="*.github.com,*.npmjs.org,*.pypi.org,YOUR_DOMAIN.com"
```

**Option 2: Use allow-all mode**
```bash
launch-agent copilot . --network-proxy allow-all
```

## Image Issues

### Image Not Found

**Symptoms:**
```
Unable to find image 'coding-agents-copilot:latest' locally
Error: No such image
```

**Solution:**

**Pull image:**
```bash
docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest
```

**Or build locally:**
```bash
./scripts/build/build.sh       # Linux/Mac
.\scripts\build\build.ps1      # Windows
```

**Verify:**
```bash
docker images | grep coding-agents
```

### Image Build Fails

**Symptoms:**
```
ERROR: failed to solve
```

**Solutions:**

**1. Check disk space:**
```bash
df -h
# Need at least 5GB free
```

**2. Clean Docker cache:**
```bash
docker system prune -a
```

**3. Update Docker:**
```bash
# Check version
docker --version

# Should be 20.10.0 or higher
# Update from docker.com
```

**4. Check Dockerfile syntax:**
```bash
# Validate Dockerfile
docker build --no-cache -f docker/base/Dockerfile .
```

**5. Try with BuildKit:**
```bash
DOCKER_BUILDKIT=1 ./scripts/build/build.sh
```

### Image Too Large

**Symptoms:**
- Build takes very long
- Out of disk space
- Images >5GB

**Solutions:**

**1. Clean unused images:**
```bash
docker image prune -a
```

**2. Remove old containers:**
```bash
docker container prune
```

**3. Check image sizes:**
```bash
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
```

**Expected sizes:**
- Base image: ~3-4GB
- Agent images: ~3-4GB each
- Proxy image: ~50MB

## Git Issues

### Auto-Push Fails

**Symptoms:**
```
❌ Failed to push changes
fatal: could not read Username
```

**Causes:**

**1. No git remote:**
```bash
# Check remote
docker exec <container> git remote -v

# Add remote if missing
docker exec <container> git remote add origin https://github.com/user/repo.git
```

**2. Authentication failure:**
```bash
# Verify gh auth on host
gh auth status

# Refresh if needed
gh auth refresh
```

**3. Branch doesn't exist on remote:**
```bash
# First push needs -u
docker exec <container> git push -u origin <branch>
```

**Solution - Disable auto-push:**
```bash
# Ephemeral containers
run-copilot --no-push

# Persistent containers
launch-agent copilot . --no-push
```

### Git Conflicts

**Symptoms:**
```
error: Your local changes would be overwritten
```

**Inside container:**
```bash
# Check status
git status

# See conflicts
git diff

# Stash changes
git stash

# Or commit changes
git add .
git commit -m "WIP"
```

### Branch Creation Fails

**Symptoms:**
```
fatal: A branch named 'copilot/feature' already exists
```

**Solutions:**

**1. Use different branch name:**
```bash
launch-agent copilot . -b feature-v2
```

**2. Force replace (with prompt):**
```bash
launch-agent copilot . -b feature
# Answer 'y' to replace
```

**3. Force replace (automatic):**
```bash
launch-agent copilot . -b feature -y
```

**4. Delete old branch manually:**
```bash
cd /path/to/repo
git branch -D copilot/feature
```

## Platform-Specific Issues

### Windows WSL Issues

**WSL2 Not Enabled:**
```powershell
# Check WSL version
wsl --version

# Install/upgrade to WSL2
wsl --install
wsl --set-default-version 2

# Restart computer
```

**WSL Path Conversion:**
```powershell
# If paths don't work, check WSL path
wsl bash -c "echo $HOME"

# Should show: /home/username
```

**Docker Desktop WSL Integration:**
1. Docker Desktop → Settings → Resources → WSL Integration
2. Enable integration for your WSL distribution
3. Click "Apply & Restart"

### Mac ARM64 (M1/M2) Issues

**Platform Mismatch:**
```
WARNING: The requested image's platform (linux/amd64) does not match the detected host platform (linux/arm64/v8)
```

**Solution:**
Images should work with emulation, but for best performance:
```bash
# Build for ARM64
docker build --platform linux/arm64 ...
```

**Rosetta Issues:**
```
exec format error
```

**Solution:**
Enable Rosetta in Docker Desktop:
1. Docker Desktop → Settings → General
2. Check "Use Rosetta for x86/amd64 emulation on Apple Silicon"
3. Apply & Restart

### Linux Distribution Issues

**RHEL/CentOS/Fedora:**

**SELinux Blocking:**
```
Permission denied mounting volumes
```

**Solution:**
```bash
# Add :z or :Z to volume mounts
-v /path:/workspace:z

# Or temporarily disable (not recommended)
sudo setenforce 0
```

**Ubuntu/Debian:**

**AppArmor Blocking:**
```
Permission denied in container
```

**Solution:**
```bash
# Check AppArmor status
sudo aa-status

# Disable Docker AppArmor profile (not recommended)
sudo ln -s /etc/apparmor.d/docker /etc/apparmor.d/disable/
sudo apparmor_parser -R /etc/apparmor.d/docker
```

## Performance Issues

### Container Slow to Start

**Causes:**
- Large images
- Slow disk I/O
- Resource limits

**Solutions:**

**1. Use pre-built images:**
```bash
docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest
# Faster than building locally
```

**2. Increase resources:**
```bash
# Launch with more resources
run-copilot --cpu 8 --memory 16g
```

**3. Check Docker Desktop resources:**
- Settings → Resources
- Increase CPUs and Memory

### Container Uses Too Much RAM

**Symptoms:**
- Host machine slows down
- Out of memory errors

**Solutions:**

**1. Limit container memory:**
```bash
run-copilot --memory 4g
launch-agent copilot . --memory 4g
```

**2. Stop unused containers:**
```bash
# List all containers
docker ps

# Stop containers you're not using
docker stop <container-name>
```

**3. Check memory usage:**
```bash
docker stats
```

### Disk Space Running Out

**Symptoms:**
```
no space left on device
```

**Solutions:**

**1. Remove unused images:**
```bash
docker image prune -a
```

**2. Remove unused containers:**
```bash
docker container prune
```

**3. Remove unused volumes:**
```bash
docker volume prune
```

**4. Full system clean:**
```bash
docker system prune -a --volumes
# WARNING: Removes everything not in use!
```

**5. Check space:**
```bash
docker system df
```

## Error Reference

### Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | N/A |
| 1 | General error | Check logs |
| 125 | Docker daemon error | Check Docker is running |
| 126 | Command cannot execute | Check permissions |
| 127 | Command not found | Install missing tool |
| 130 | Terminated by Ctrl+C | Normal interruption |
| 137 | Killed (OOM) | Increase memory limit |

### Common Error Messages

**"Cannot connect to Docker daemon"**
→ Start Docker Desktop or `sudo systemctl start docker`

**"Permission denied while connecting to Docker socket"**
→ Add user to docker group: `sudo usermod -aG docker $USER`

**"Port is already allocated"**
→ Stop conflicting container or use different port

**"No space left on device"**
→ Run `docker system prune -a`

**"Unable to find image"**
→ Pull image: `docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest`

**"Network timed out"**
→ Check internet connection and firewall

**"Authentication required"**
→ Run `gh auth login`

**"Not a git repository"**
→ Run from within a git repository

**"Branch name invalid"**
→ Use only alphanumeric, /, _, -, . in branch names

## Getting More Help

### Diagnostic Commands

```bash
# System info
docker info
docker version

# Container info
docker ps -a
docker logs <container-name>
docker inspect <container-name>

# Network info
docker network ls
docker network inspect bridge

# Image info
docker images
docker history <image-name>

# Resource usage
docker stats
docker system df
```

### Enable Debug Logging

```bash
# Docker Desktop: Settings → Docker Engine
# Add: "debug": true

# Linux: /etc/docker/daemon.json
{
  "debug": true,
  "log-level": "debug"
}

# Restart Docker
sudo systemctl restart docker
```

### Report Issues

If you're stuck:

1. **Check existing issues:** [GitHub Issues](https://github.com/novotnyllac/CodingAgents/issues)
2. **Run diagnostics:** Include output from diagnostic commands above
3. **Create new issue:** Provide:
   - OS and version
   - Docker version
   - Command that failed
   - Full error message
   - Relevant logs

### Additional Resources

- [Getting Started Guide](docs/getting-started.md)
- [Usage Guide](USAGE.md)
- [Architecture Documentation](docs/architecture.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Docker Documentation](https://docs.docker.com/)
- [GitHub CLI Documentation](https://cli.github.com/manual/)
