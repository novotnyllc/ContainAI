# fn-47-extensibility-agent-integration.2 Startup Hooks - Implement hooks/startup.d/ support

## Description

Allow users to add executable scripts that run at container startup without needing to understand systemd. Hooks can be defined at two levels:

1. **Template-level** - In `~/.config/containai/templates/<name>/hooks/startup.d/` - shared across all workspaces using that template
2. **Workspace-level** - In `.containai/hooks/startup.d/` - specific to one project

Both are merged at runtime: template hooks run first, then workspace hooks.

### Directory Structure

```
# Template-level (shared across workspaces)
~/.config/containai/templates/
└── my-template/
    ├── Dockerfile
    └── hooks/
        └── startup.d/
            ├── 10-install-common-tools.sh
            └── 20-setup-services.sh

# Workspace-level (project-specific)
project/
└── .containai/
    └── hooks/
        └── startup.d/
            ├── 30-project-deps.sh
            └── 40-custom-setup.sh
```

### Hook Resolution Order

1. Template hooks first (sorted): `~/.config/containai/templates/<template>/hooks/startup.d/*.sh`
2. Workspace hooks second (sorted): `.containai/hooks/startup.d/*.sh`

This allows templates to set up common infrastructure, while workspaces add project-specific setup.

### Implementation

1. **Extend `src/container/containai-init.sh`** - Add hook execution after existing init logic:
   ```bash
   run_hooks() {
       local hooks_dir="$1"
       [[ -d "$hooks_dir" ]] || return 0

       # Set working directory
       cd /home/agent/workspace || true

       # Deterministic ordering with LC_ALL=C
       local hook
       while IFS= read -r hook; do
           [[ -z "$hook" ]] && continue
           if [[ ! -x "$hook" ]]; then
               log "WARNING: Skipping non-executable hook: $hook"
               continue
           fi
           log "Running startup hook: $hook"
           if ! "$hook"; then
               log "ERROR: Startup hook failed: $hook"
               exit 1
           fi
       done < <(find "$hooks_dir" -maxdepth 1 -name '*.sh' -type f | LC_ALL=C sort)
   }

   # Template hooks first, then workspace hooks
   run_hooks "/etc/containai/template-hooks/startup.d"
   run_hooks "/home/agent/workspace/.containai/hooks/startup.d"
   ```

2. **Fail-Fast Mechanism** - Update systemd dependencies:
   Change from `Wants=` to `Requires=` in:
   - `src/services/ssh.service.d/containai.conf:9` - Change `Wants=containai-init.service` to `Requires=containai-init.service`
   - `src/services/docker.service.d/containai.conf:9` - Change `Wants=containai-init.service` to `Requires=containai-init.service`

   This ensures that if containai-init.service fails (hook failure), dependent services won't start, making the container effectively unusable.

3. **Mount paths (handled by Task 4):**
   - Template hooks mounted to `/etc/containai/template-hooks/`
   - Workspace hooks accessed directly at workspace path

4. **Execution context:**
   - Scripts run as agent user (not root) - via `User=agent` in containai-init.service
   - `sudo` available if needed
   - Working directory: `/home/agent/workspace` (explicit cd in run_hooks)
   - stdout/stderr logged to container journal

5. **Error handling:**
   - Non-zero exit from any hook fails container start (service fails, dependents fail)
   - Clear error message identifying which hook failed
   - Hooks should be idempotent (safe to re-run)

### Example Use Cases

**Template: ML development environment**
```bash
# ~/.config/containai/templates/ml/hooks/startup.d/10-gpu-setup.sh
#!/bin/bash
# Runs for all ML projects
nvidia-smi || echo "No GPU detected"
pip install torch --quiet
```

**Workspace: Specific project**
```bash
# project/.containai/hooks/startup.d/30-deps.sh
#!/bin/bash
# Runs only for this project
pip install -r requirements.txt
```

### Testing

- Create test with hooks at both template and workspace levels
- Verify template hooks run before workspace hooks
- Verify hooks run as agent user
- Verify failed hook stops container start (dependent services fail)
- Verify non-executable files are skipped with warning

## Acceptance

- [ ] Template hooks at `~/.config/containai/templates/<name>/hooks/startup.d/*.sh` supported
- [ ] Workspace hooks at `.containai/hooks/startup.d/*.sh` supported
- [ ] Template hooks run before workspace hooks
- [ ] Scripts run in deterministic sorted order (`LC_ALL=C sort`)
- [ ] Scripts run as agent user with sudo available
- [ ] Working directory is `/home/agent/workspace`
- [ ] Non-executable files skipped with warning (logged)
- [ ] Failed script (non-zero exit) fails container start
- [ ] Clear error message shows which hook failed
- [ ] ssh.service.d/containai.conf uses `Requires=containai-init.service`
- [ ] docker.service.d/containai.conf uses `Requires=containai-init.service`
- [ ] Integration test added

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
