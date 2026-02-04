# Task fn-51.5: Remove hardcoded aliases from Dockerfile.agents, use generated wrappers

**Status:** pending
**Depends on:** fn-51.4

## Objective

Replace hardcoded alias block in Dockerfile with generated wrapper script, ensuring wrappers work in both interactive and non-interactive shells.

## Context

Current Dockerfile.agents lines 161-168:
```dockerfile
RUN printf '%s\n' \
    'alias claude="claude --dangerously-skip-permissions"' \
    'alias codex="codex --dangerously-bypass-approvals-and-sandbox"' \
    'alias kimi="kimi --yolo"' \
    'alias kimi-cli="kimi-cli --yolo"' \
    ...
    > /home/agent/.bash_aliases
```

This should use generated wrappers that work in both interactive and non-interactive SSH.

## Implementation

1. Remove the alias `RUN` block from Dockerfile.agents (lines 157-168)

2. Add new blocks to setup wrapper infrastructure:

```dockerfile
# =============================================================================
# AGENT LAUNCH WRAPPERS
# Generated from manifest [agent] sections
# =============================================================================
# Create bash_env.d directory for wrapper scripts
RUN mkdir -p /home/agent/.bash_env.d

# Copy generated wrappers
COPY artifacts/container-generated/agent-wrappers.sh /home/agent/.bash_env.d/containai-agents.sh
```

3. **Update `.bash_env` to source `.bash_env.d/*.sh`:**
   Add to Dockerfile (or modify existing .bash_env setup):
   ```bash
   RUN cat >> /home/agent/.bash_env << 'BASHENV'
   # Source all bash_env.d scripts (for wrappers, etc)
   for f in /home/agent/.bash_env.d/*.sh; do
       [[ -r "$f" ]] && source "$f"
   done
   BASHENV
   ```

4. **Update `.bashrc` to source `.bash_env`:**
   This ensures interactive shells also get the wrappers:
   ```bash
   RUN cat >> /home/agent/.bashrc << 'BASHRC'
   # Source .bash_env for wrapper functions (if not already sourced)
   [[ -z "$_BASH_ENV_SOURCED" ]] && [[ -f ~/.bash_env ]] && source ~/.bash_env
   BASHRC
   ```

   And in `.bash_env` add a guard:
   ```bash
   export _BASH_ENV_SOURCED=1
   ```

5. Ensure proper sourcing chain:
   - Non-interactive SSH: `BASH_ENV=/home/agent/.bash_env` → sources `.bash_env.d/*.sh` → wrappers available
   - Interactive non-login: `.bashrc` → sources `.bash_env` → sources `.bash_env.d/*.sh` → wrappers available
   - Login: `.bash_profile` → sources `.bashrc` → same chain

6. Update build.sh to generate wrappers before Docker build:
```bash
./src/scripts/gen-agent-wrappers.sh src/manifests artifacts/container-generated/agent-wrappers.sh
```

## Acceptance Criteria

- [ ] Hardcoded alias block removed from Dockerfile.agents
- [ ] `.bash_env.d/` directory created in container
- [ ] Generated wrappers copied to `/home/agent/.bash_env.d/containai-agents.sh`
- [ ] `.bash_env` updated to source `.bash_env.d/*.sh`
- [ ] `.bashrc` updated to source `.bash_env` (with guard to prevent double-sourcing)
- [ ] `ssh container 'claude --help'` works (non-interactive - **critical**)
- [ ] Interactive `claude --help` works
- [ ] All agent commands invoke with default autonomous flags
- [ ] `kimi-cli --help` works (alias support)
- [ ] Image builds successfully

## Test Cases

```bash
# Build image
./src/build.sh

# Start container
cai run --container test

# Test non-interactive (most important - this is what breaks without BASH_ENV)
ssh test 'claude --help'
ssh test 'codex --help'
ssh test 'type claude'  # should show "claude is a function"

# Test interactive
ssh test
claude --help
codex --help
type claude

# Test kimi alias
ssh test 'kimi --help'
ssh test 'kimi-cli --help'  # both should work
```

## Notes

- Must run gen-agent-wrappers.sh before Docker build in build.sh
- `BASH_ENV` is already set in Dockerfile.base - we just need to source wrappers from it
- `.bashrc` sourcing `.bash_env` is required for interactive shells
- Use guard variable to prevent double-sourcing
- Verify kimi + kimi-cli both work (alias support from Task 2)
