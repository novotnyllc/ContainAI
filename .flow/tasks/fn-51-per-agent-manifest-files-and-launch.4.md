# Task fn-51.4: Generate launch wrapper functions from manifest [agent] sections

**Status:** pending
**Depends on:** fn-51.2, fn-51.3

## Objective

Create generator script that produces shell functions for agent launch with default args, ensuring they work in both interactive and non-interactive SSH sessions.

## Context

Replace hardcoded aliases with generated functions that:
- Prepend default args from manifest
- Work in interactive shells (login/non-login)
- **Critical:** Work in non-interactive SSH (`ssh container 'claude --help'`)

**Non-interactive SSH issue:** `/etc/profile.d/` is NOT sourced for `ssh <host> 'command'` - sshd runs shell with `-c` which skips profile.d. Container uses `BASH_ENV=/home/agent/.bash_env` to handle this.

## Implementation

1. Create `src/scripts/gen-agent-wrappers.sh`:

```bash
#!/usr/bin/env bash
# Generate agent launch wrapper functions
# Usage: gen-agent-wrappers.sh <manifests-dir> <output-file>
#
# Reads [agent] sections from manifests (via parse-toml.py --emit-agents)
# and generates shell functions
```

2. Output format (`artifacts/container-generated/agent-wrappers.sh`):

```bash
# Generated agent launch wrappers
# Source this file for agent commands with default autonomous flags

# Claude Code
claude() {
    command claude --dangerously-skip-permissions "$@"
}

# Codex
codex() {
    command codex --dangerously-bypass-approvals-and-sandbox "$@"
}

# Gemini (optional)
if command -v gemini >/dev/null 2>&1; then
gemini() {
    command gemini --yolo "$@"
}
fi

# Kimi (optional) - includes kimi-cli alias
if command -v kimi >/dev/null 2>&1; then
kimi() {
    command kimi --yolo "$@"
}
kimi-cli() {
    command kimi-cli --yolo "$@"
}
fi

# ... etc
```

3. Function characteristics:
   - Use `command` builtin to invoke real binary (avoid recursion)
   - Optional agents wrapped in `command -v` check
   - Prepend default_args, then "$@" for user args
   - Handle `aliases` array: generate wrapper for each alias
   - Only generate wrapper if `default_args` is non-empty
   - Comment with agent name before each function

4. **Critical: Place wrappers where BASH_ENV sources them:**
   - Create `/home/agent/.bash_env.d/` directory
   - Copy wrappers to `/home/agent/.bash_env.d/containai-agents.sh`
   - Update `.bash_env` to source `.bash_env.d/*.sh`

5. Update `build.sh` to run generator before Docker build

## Acceptance Criteria

- [ ] `src/scripts/gen-agent-wrappers.sh` created
- [ ] Generates functions for all agents with `[agent]` section AND non-empty `default_args`
- [ ] Handles `aliases` array (generates wrapper for each alias)
- [ ] Optional agents wrapped in `command -v` check
- [ ] Output file placed in `/home/agent/.bash_env.d/containai-agents.sh`
- [ ] `.bash_env` updated to source `.bash_env.d/*.sh`
- [ ] Functions work in interactive bash
- [ ] **Functions work in SSH non-interactive commands** (`ssh container 'claude --help'`)

## Test Cases

```bash
# After image build:
# Test interactive
ssh container
claude --help  # should work

# Test non-interactive (critical - this is the one that often breaks)
ssh container 'claude --help'       # MUST work
ssh container 'type claude'         # should show function definition
```

## Notes

- Uses JSON output from `parse-toml.py --emit-agents` for proper array handling
- `/etc/profile.d/` is NOT sufficient for non-interactive SSH
- `BASH_ENV` is the correct mechanism (already set in Dockerfile.base)
- `command` builtin prevents function recursion
