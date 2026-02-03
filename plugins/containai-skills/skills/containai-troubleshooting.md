# ContainAI Troubleshooting

Use this skill when: encountering errors, diagnosing issues, fixing common problems, understanding error codes.

## Diagnostic Commands

Always start with:

```bash
cai doctor          # Check system status
cai status          # Check container status
```

## Exit Codes

| Code | Meaning | Resolution |
|------|---------|------------|
| 0 | Success | - |
| 1 | General error | Check error message |
| 11 | Container failed to start | Run `cai doctor`, check Docker |
| 12 | SSH setup failed | Check SSH config, run `cai doctor` |
| 13 | SSH connection failed | Container may be starting, retry |
| 14 | Host key mismatch | Run `cai --fresh` to recreate |
| 15 | Container not owned by ContainAI | Use different name or remove manually |

## Common Errors

### "Sysbox runtime not found"

**Cause:** Sysbox is not installed or not configured.

**Fix:**
```bash
cai setup                # Run setup to install Sysbox
cai doctor               # Verify installation
```

### "Container failed to start"

**Cause:** Docker daemon issues, resource limits, or image problems.

**Fix:**
```bash
# Check Docker
docker ps

# Check container logs
docker logs <container-name>

# Try fresh start
cai run --fresh
```

### "SSH connection refused"

**Cause:** Container is still starting, SSH service not ready.

**Fix:**
```bash
# Wait and retry (automatic with cai commands)
cai shell

# If persistent, check container status
cai status

# Force fresh container
cai run --fresh
```

### "Host key verification failed"

**Cause:** Container was recreated with new SSH keys, but old keys cached.

**Fix:**
```bash
# Automatic fix: recreate container
cai run --fresh

# Manual fix: clean SSH known hosts
ssh-keygen -R [localhost]:<port>
```

### "Permission denied" in container

**Cause:** Volume permissions or file ownership issues.

**Fix:**
```bash
# Fix volume permissions
cai doctor fix volume --all

# Or recreate container
cai run --fresh
```

### "No such container"

**Cause:** Container was removed or never created.

**Fix:**
```bash
# Create container
cai run
```

### "Container exists but not owned by ContainAI"

**Cause:** Container with same name exists but wasn't created by ContainAI.

**Fix:**
```bash
# Use different container name
cai run --container different-name

# Or remove existing container manually
docker rm <container-name>
cai run
```

### "Port already in use"

**Cause:** SSH port conflict with another process or container.

**Fix:**
```bash
# Stop conflicting containers
cai stop --all

# Or expand port range
cai config set ssh.port_range_end 2422
```

### "Docker context not found"

**Cause:** ContainAI Docker context not configured.

**Fix:**
```bash
cai setup
```

### "Image not found"

**Cause:** Base image not pulled or registry unavailable.

**Fix:**
```bash
# Pull image manually
docker pull ghcr.io/containai/containai:stable

# Or rebuild template
cai doctor fix template default
```

### "Template build failed"

**Cause:** Dockerfile syntax error or missing dependencies.

**Fix:**
```bash
# Check template Dockerfile
cat ~/.config/containai/templates/<name>/Dockerfile

# Rebuild with verbose output
cai run --fresh --verbose
```

### "Network policy blocked request"

**Cause:** Egress restricted by `.containai/network.conf`.

**Fix:**
```bash
# Check network config
cat .containai/network.conf

# Add required domain
echo "allow = api.example.com" >> .containai/network.conf

# Restart container
cai run --fresh
```

### "Import failed: container not running"

**Cause:** Hot-reload requires running container.

**Fix:**
```bash
# Start container first
cai run --detached

# Then import
cai import /path/to/workspace
```

### "Export failed: volume not found"

**Cause:** Data volume doesn't exist or wrong volume name.

**Fix:**
```bash
# Check volume exists
docker volume ls | grep containai

# Export with specific volume
cai export --data-volume <correct-name>
```

## Startup Hook Errors

### "Hook failed: exit code N"

**Cause:** Startup script exited with error.

**Fix:**
```bash
# Check hook script
cat .containai/hooks/startup.d/<script>.sh

# Fix script errors
chmod +x .containai/hooks/startup.d/<script>.sh

# Test locally
bash -x .containai/hooks/startup.d/<script>.sh
```

### "Hook not executable"

**Cause:** Script missing execute permission.

**Fix:**
```bash
chmod +x .containai/hooks/startup.d/*.sh
```

## Resource Issues

### "Out of memory"

**Cause:** Container memory limit exceeded.

**Fix:**
```bash
# Increase memory limit
cai run --memory 8g

# Or set in config
cai config set container.memory 8g
```

### "CPU throttling"

**Cause:** High CPU usage hitting limits.

**Fix:**
```bash
cai run --cpus 4
```

## Recovery Procedures

### Complete Reset

When all else fails:

```bash
# 1. Stop and remove all containers
cai stop --all --remove

# 2. Clean up volumes (WARNING: loses data!)
docker volume ls | grep cai- | xargs docker volume rm

# 3. Re-run setup
cai setup --force

# 4. Verify
cai doctor

# 5. Start fresh
cai run
```

### Reset Single Workspace

```bash
# Fresh container, new data volume
cai run --reset
```

### Recover Data

Before destructive actions:

```bash
# Export data
cai export -o ~/backup.tgz

# After reset, restore
cai import --from ~/backup.tgz
```

## Debug Mode

For detailed troubleshooting:

```bash
# Verbose output
cai run --verbose

# Dry-run to see what would happen
cai run --dry-run

# Check container logs
docker logs <container-name>

# Shell into container manually
docker exec -it <container-name> bash
```

## Getting Help

### Log Collection

Collect diagnostics for bug reports:

```bash
cai doctor --json > doctor.json
cai status --json > status.json
docker logs <container-name> > container.log 2>&1
```

### Common Log Locations

**Host:**
- ContainAI config: `~/.config/containai/`
- SSH configs: `~/.ssh/containai.d/`
- Workspace state: `~/.local/state/containai/`

**Container:**
- Init logs: `journalctl -u containai-init`
- SSH logs: `journalctl -u ssh`
- Hook output: In container init logs

## Gotchas

### Cached DNS

Network policies resolve domains at container start. If IPs change:
```bash
cai run --fresh
```

### SSH Agent

If git push fails with "Permission denied":
```bash
# Check agent on host
ssh-add -l

# Re-add keys if needed
ssh-add ~/.ssh/id_ed25519
```

### Multiple Projects

Each workspace path gets its own container. Ensure you're in the right directory:
```bash
pwd
cai status
```

### Docker Context

ContainAI uses its own Docker context. If `docker ps` shows different containers:
```bash
# Use ContainAI's context
cai docker ps

# Or set context explicitly
docker --context containai-docker ps
```

## Related Skills

- `containai-setup` - System configuration
- `containai-lifecycle` - Container management
- `containai-sync` - Data operations
