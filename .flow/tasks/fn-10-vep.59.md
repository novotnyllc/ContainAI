# fn-10-vep.59 Implement cai import for hot-reload of config

## Description
Implement `cai import` for hot-reload of config into running container.

**Size:** M
**Files:** lib/import.sh (new or extend existing)

## Approach

1. `cai import /path/to/workspace` reloads config into running container
2. Hot-reload targets:
   - Environment variables from .env (persistent via bashrc.d hook)
   - Credentials: API tokens synced to volume, SSH via agent forwarding
   - Git config
3. Uses SSH to inject changes (not docker exec), with retry and host-key recovery
4. Does NOT restart container

## Key context

- This is the "hot reload" mechanism - no need for `--fresh`
- Re-runs credential sync that normally happens at container start
- Validates container is running first
## Acceptance
- [x] `cai import /path/to/workspace` command works
- [x] Reloads .env variables into container (via bashrc.d hook for persistence)
- [x] Reloads credentials: API tokens synced to volume, SSH via agent forwarding
      (SSH keys stay on host for security - use `ssh -A` or config `forward_agent = true`)
- [x] Reloads git config (copies from data volume to agent home)
- [x] Uses SSH (not docker exec) with retry and host-key recovery
- [x] Clear output showing what was imported
- [x] Errors if container not running
## Done summary
Implemented hot-reload for `cai import` command. When a workspace path is provided (positional or via --workspace), configs are synced to the data volume AND reloaded into the running container via SSH without restarting. The command validates the container is running before proceeding and shows clear output of what was reloaded (env vars and git config).
## Evidence
- Commits: 2cb7f0579391e68d3c7ee509b78f8f92ee7b3388
- Tests: shellcheck -x src/containai.sh src/lib/import.sh, source src/containai.sh && _containai_import_help
- PRs:
