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
- [x] HISTFILE points to data volume (`/mnt/agent-data/shell/history`)
- [x] History persists across `--fresh`
- [x] History is per-workspace (different workspaces have separate history)
- [x] Works for bash (container default shell)

Note: Zsh is not installed in the container. The .zshrc/.zprofile sync entries are for importing user configs to use with bash (task .8).

## Done summary
Added bash history persistence to the data volume so command history survives `--fresh` container resets.

**Changes:**
- `src/container/Dockerfile.agents`: Added bashrc.d script `02-shell-history.sh` that sets:
  - `HISTFILE=/mnt/agent-data/shell/history`
  - `HISTSIZE=10000`
  - `HISTFILESIZE=20000`

**How it works:**
- The bashrc.d script is sourced on every interactive shell startup
- HISTFILE points to the data volume which is preserved across `--fresh`
- Each workspace has its own data volume, so history is per-workspace
- The shell directory (`/mnt/agent-data/shell/`) is already created by containai-init

## Evidence
- Commits: (pending)
- Tests: Manual verification: bashrc.d script sets HISTFILE to /mnt/agent-data/shell/history
- PRs:
