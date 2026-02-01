# fn-42-cli-ux-fixes-hostname-reset-wait-help.5 Per-workspace bash/zsh history persistence

## Description
Shell history should persist per-workspace in the data volume, so each workspace has its own command history that survives `--fresh`.

**Size:** S
**Files:** `src/container/Dockerfile.agents`, `src/lib/import.sh`, `src/sync-manifest.toml`

## Approach

1. Store history in data volume at `/mnt/agent-data/shell/history`
2. Set in container bashrc.d script:
   ```bash
   export HISTFILE=/mnt/agent-data/shell/history
   export HISTSIZE=10000
   export HISTFILESIZE=20000
   ```
3. For zsh (task .8), similar with `HISTFILE` for zsh

Since containers are per-workspace, history is automatically per-workspace.

## Key context

- Data volume is workspace-specific (one volume per workspace)
- Container already has `/mnt/agent-data/shell/` directory
- bashrc.d scripts sourced on shell startup
## Acceptance
- [ ] HISTFILE points to data volume
- [ ] History persists across `--fresh`
- [ ] History is per-workspace (different workspaces have separate history)
- [ ] Works for both bash and zsh
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
