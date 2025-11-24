# Operations, Troubleshooting, and FAQ

Reference this guide when something goes wrong or when you need advanced launch patterns.

## Troubleshooting

### Authentication Warnings

If you see:
```
⚠️ WARNING: GitHub Copilot authentication not found!
```

**Solution:**
1. Run `gh auth login` on your host
2. Restart container: `docker restart copilot-app`

### MCP Servers Not Working

Check the host secrets file exists (the renderer reads it before each launch):
```bash
ls ~/.config/containai/mcp-secrets.env
```

Verify tokens are valid:
- GitHub: https://github.com/settings/tokens
- Context7: https://context7.ai/

Restart the launcher after adding/updating secrets so a fresh session manifest is generated.

### Container Already Exists

If you see "Container already exists":
```bash
# Remove old container
docker rm -f copilot-app

# Launch again
.\launch-agent.ps1
```

### Git Push Fails

```bash
# Check remotes
git remote -v

# Check which remote is default
git config remote.pushDefault

# Push to the managed local remote explicitly (inside the container)
git push local copilot/feature-auth

# Ready to publish? Switch to the host repo (already up to date)
cd ~/projects/app
git push origin copilot/feature-auth
```

### Can't Connect from VS Code

1. Ensure container is running: `docker ps`
2. Install **Dev Containers** extension (ms-vscode-remote.remote-containers)
3. Try attaching with the Docker extension instead

## Advanced Usage

### Force Specific Container Runtime

By default, scripts auto-detect the first `docker` CLI on your PATH. To pin a specific Docker binary (for example, a custom install location), set `CONTAINER_RUNTIME=docker` before launching:

```bash
export CONTAINER_RUNTIME=docker
launch-agent copilot
```

```powershell
$env:CONTAINER_RUNTIME = "docker"
.\launch-agent.ps1 copilot
```

### Custom Container Name

```powershell
.\launch-agent.ps1 copilot . --name experiment-1
# Creates: copilot-experiment-1
```

### Specify Git Remote Manually

Edit inside container:
```bash
git remote add upstream https://github.com/upstream/repo.git
git fetch upstream
```

### Use docker-compose (Advanced)

```bash
# Create .env
cp .env.example .env

# Start services
REPO_PATH=/path/to/repo docker-compose up -d

# Connect
docker exec -it coding-agent bash
```

Most users should use `launch-agent` instead.

## Command Reference

Quick commands are listed here; see [docs/usage/cli-reference.md](cli-reference.md) for the complete list and flag reference.

### Run Agent (Recommended)
```bash
# Bash
run-copilot-dev [directory] [--no-push] [--help]   # use run-copilot in prod bundles
run-codex-dev [directory] [--no-push] [--help]
run-claude-dev [directory] [--no-push] [--help]

# PowerShell
run-copilot-dev.ps1 [directory] [-NoPush] [-Help]
run-codex-dev.ps1 [directory] [-NoPush] [-Help]
run-claude-dev.ps1 [directory] [-NoPush] [-Help]
```

**Parameters:**
- `directory`: Local path (default: current directory)
- `-NoPush`/`--no-push`: Disable auto-push on exit
- `-Help`/`--help`: Show usage information

### Launch Agent (Advanced)
```powershell
# PowerShell
.\host\launchers\entrypoints\launch-agent-dev.ps1 <agent> [source] [-Branch name] [-Name custom]

# Bash
./host/launchers/entrypoints/launch-agent-dev <agent> [source] [-b name] [--name custom]
```

**Parameters:**
- `agent`: Agent type (required): copilot, codex, or claude
- `source`: Directory path or GitHub URL (default: current dir)
- `-Branch`/`-b`: Branch name (default: current branch or "main")
- `-Name`/`--name`: Custom container name (default: auto-generated)

For container management (stop, start, remove), see [docs/usage/launchers.md](launchers.md#managing-containers).

## Examples

### Single agent, quick task

```powershell
.\host\launchers\entrypoints\launch-agent-dev.ps1 copilot
# Work in container
# Push changes
docker rm -f copilot-myrepo
```

### Long-term development

```powershell
.\host\launchers\entrypoints\launch-agent-dev.ps1 copilot C:\projects\app -b feature-api
# Connect from VS Code
# Work over days/weeks
# Container persists until you remove it
```

### Multiple features, multiple agents

```powershell
.\launch-agent.ps1 copilot . -b backend-api
.\launch-agent.ps1 claude . -b frontend-redesign
.\launch-agent.ps1 codex . -b tests
```

### Experiment with open source

```powershell
.\launch-agent.ps1 copilot https://github.com/microsoft/vscode -b explore
# Explore in isolated environment
# No impact on host
docker rm -f copilot-vscode  # Clean up when done
```

## FAQ

**Q: Do I need to build the images myself?**  
A: No if using published images. Yes if making custom changes.

**Q: Where are my changes stored?**  
A: Inside the container at `/workspace`. They're persistent until you remove the container.

**Q: How do I get my changes out?**  
A: Inside the container run `git push` to update the managed `local` remote. A background sync fast-forwards the matching branch in your host repo, so you can immediately `git push origin <branch>` from the host when you're ready. (If you set `CONTAINAI_DISABLE_AUTO_SYNC=1`, manually `git fetch ~/.containai/local-remotes/<hash>.git <branch>` before pushing.)

**Q: Can I edit files from host while container is running?**  
A: No, the workspace is isolated inside the container. Use VS Code Remote to edit.

**Q: What if I accidentally delete the container?**  
A: If you pushed your changes to git, you can recover. Otherwise, they're lost. Always push!

**Q: Do all agents see the same code?**  
A: No, each container has its own isolated copy of the repository.

**Q: How much disk space do containers use?**  
A: Images: ~3-4 GB base + 100MB per agent (Ubuntu 24.04, .NET SDKs with workloads, Playwright). Containers: depends on your code size.

**Q: Can I use this without VS Code?**  
A: Yes, use `docker exec -it <container> bash` for a terminal.

---

**Next Steps:**
- See [docs/development/build.md](../development/build.md) if building images yourself
- See [docs/security/architecture.md](../security/architecture.md) for system design
- See [docs/usage/network-proxy.md](network-proxy.md) for network configuration
- See [scripts/test/README.md](../../scripts/test/README.md) for testing procedures
