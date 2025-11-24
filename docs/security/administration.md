# Operations Guide

This guide is for system administrators and DevOps engineers responsible for maintaining the ContainAI environment.

## System Health

### Verification
Run the built-in verification script to ensure the host environment is healthy:

```bash
./host/utils/verify-prerequisites.sh
```

### Component Status
Check the status of running agents and sidecars:

```bash
# List all agents
list-agents --all

# Check sidecar status (Proxy/Log Forwarder)
docker ps --filter "label=containai.type=sidecar"
```

## Updates & Maintenance

### Updating the Host Tools
The host tools (launchers, scripts) are versioned via the Payload. To update to the latest version:

```bash
# Update to latest stable
curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash

# Update to a specific channel
curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash -s -- --channel nightly
```

### Updating Container Images
Images are pulled automatically by the launchers based on your active channel (dev, prod, nightly). Launchers **do not** use the `latest` tag. To force an update of all images for your specific channel (e.g., `prod`):

```bash
# Pull the specific tag for your channel
docker pull ghcr.io/novotnyllc/containai:prod
docker pull ghcr.io/novotnyllc/containai-copilot:prod
# ... repeat for other agents
```

> **Note**: Never pull `:latest`. The system relies on pinned channel tags (`:dev`, `:prod`, `:nightly`) or specific version digests to ensure compatibility between the host tools and the container runtime.

### Cleaning Up
Over time, Docker artifacts can consume significant disk space.

```bash
# Remove stopped agent containers
remove-agent --all

# Prune unused images (dangling)
docker image prune

# Prune all unused images (including old versions of agents)
docker image prune -a
```

## Observability & Logging

### Audit Logs
Security-relevant events (session starts, secret access, overrides) are logged to the host:

- **Path**: `~/.config/containai/security-events.log`
- **Format**: JSON Lines

**Integration**: Configure your SIEM (Splunk, Fluentd, etc.) to tail this file.

### Container Logs
Standard output from the agents is captured by Docker:

```bash
docker logs <container-name>
```

### Network Logs (Proxy)
If running with `--network-proxy squid`, traffic logs are captured in the proxy sidecar.

```bash
docker logs containai-proxy
```

## Data Management

### Local Remotes
ContainAI uses bare git repositories in `~/.containai/local-remotes` to synchronize changes. These are standard git repos.

**Maintenance**:
- They are not automatically garbage collected. You can run `git gc` inside them if they grow too large.
- If a remote becomes corrupted, you can safely delete the specific `<hash>.git` folder. The next launch will recreate it (though unpushed commits in the container would be lost).

## Disaster Recovery

### Reinstallation
If the installation becomes corrupted:

1.  **Uninstall**: Follow the [Uninstall Guide](#uninstalling-containai).
2.  **Reinstall**: Run the `install.sh` script.

### Recovering Work
If a container is accidentally deleted but the `local-remote` exists:
1.  Navigate to `~/.containai/local-remotes`.
2.  Find the hash corresponding to your repo (check `config` inside the bare repos or look at timestamps).
3.  Clone/Fetch from that bare repo to recover the commits.

```bash
git clone ~/.containai/local-remotes/<hash>.git recovered-work
```

## Uninstalling ContainAI

To completely remove ContainAI from your system:

1.  **Stop all running agents**:
    ```bash
    docker stop $(docker ps -q --filter name=containai-*)
    ```

2.  **Remove Docker resources**:
    ```bash
    # Remove containers
    docker rm $(docker ps -aq --filter name=containai-*)
    
    # Remove images
    docker rmi $(docker images -q ghcr.io/novotnyllc/containai-*)
    
    # Remove volumes (optional - deletes cached data)
    docker volume rm $(docker volume ls -q --filter name=containai-*)
    ```

3.  **Remove the installation**:
    **Linux / macOS:**
    ```bash
    sudo rm -rf /opt/containai
    ```
    **Windows:**
    ```powershell
    Remove-Item -Recurse -Force "$env:LOCALAPPDATA\ContainAI"
    ```

4.  **Remove configuration**:
    ```bash
    rm -rf ~/.config/containai
    rm -rf ~/.containai
    ```

5.  **Clean up PATH**:
    - If you added `/opt/containai/current/host/launchers/entrypoints` to your PATH, remove it from your shell profile.
