# Task fn-51.5: Remove hardcoded aliases from Dockerfile.agents, use generated wrappers

**Status:** pending
**Depends on:** fn-51.4

## Objective

Replace hardcoded alias block in Dockerfile with generated wrapper script.

## Context

Current Dockerfile.agents lines 161-168:
```dockerfile
RUN printf '%s\n' \
    'alias claude="claude --dangerously-skip-permissions"' \
    'alias codex="codex --dangerously-bypass-approvals-and-sandbox"' \
    ...
    > /home/agent/.bash_aliases
```

This should use the generated wrappers instead.

## Implementation

1. Remove the alias `RUN` block from Dockerfile.agents (lines 157-168)

2. Add new block to copy generated wrappers:

```dockerfile
# =============================================================================
# AGENT LAUNCH WRAPPERS
# Generated from manifest [agent] sections
# =============================================================================
COPY artifacts/container-generated/agent-wrappers.sh /etc/profile.d/containai-agents.sh
```

3. Ensure wrappers are sourced:
   - Login shells: `/etc/profile.d/` is automatic
   - Interactive non-login: `.bashrc` already sources profile.d on this image
   - Non-interactive SSH: Verify `bash -c` picks up profile.d

4. Update build.sh to generate wrappers before Docker build:
```bash
./src/scripts/gen-agent-wrappers.sh src/manifests artifacts/container-generated/agent-wrappers.sh
```

## Acceptance Criteria

- [ ] Hardcoded alias block removed from Dockerfile.agents
- [ ] Generated wrappers copied to container
- [ ] `ssh container claude --help` works (non-interactive)
- [ ] Interactive `claude --help` works
- [ ] All agent commands invoke with default autonomous flags
- [ ] Image builds successfully

## Test Cases

```bash
# Build image
./src/build.sh

# Test interactive
cai run --container test
ssh test 'claude --help'
ssh test 'codex --help'
ssh test 'gemini --help'

# Test non-interactive
ssh test bash -c 'claude --help'
```

## Notes

- Must run gen-agent-wrappers.sh before Docker build in build.sh
- Verify kimi-cli alias also works (was `alias kimi-cli="kimi-cli --yolo"`)
