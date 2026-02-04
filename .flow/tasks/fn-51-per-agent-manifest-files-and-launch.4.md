# Task fn-51.4: Generate launch wrapper functions from manifest [agent] sections

**Status:** pending
**Depends on:** fn-51.2, fn-51.3

## Objective

Create generator script that produces shell functions for agent launch with default args.

## Context

Replace hardcoded aliases with generated functions that:
- Prepend default args from manifest
- Can be extended to run pre-launch hooks (symlink setup)
- Work in interactive and non-interactive shells

## Implementation

1. Create `src/scripts/gen-agent-wrappers.sh`:

```bash
#!/usr/bin/env bash
# Generate agent launch wrapper functions
# Usage: gen-agent-wrappers.sh <manifests-dir> <output-file>
#
# Reads [agent] sections from manifests and generates shell functions
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

# ... etc
```

3. Function characteristics:
   - Use `command` builtin to invoke real binary (avoid recursion)
   - Optional agents wrapped in `command -v` check
   - Prepend default_args, then "$@" for user args
   - Comment with agent name before each function

4. Update `Dockerfile.agents`:
   - Copy generated wrappers to `/etc/profile.d/containai-agents.sh`
   - Remove hardcoded alias block

5. Update `build.sh` to run generator before Docker build

## Acceptance Criteria

- [ ] `src/scripts/gen-agent-wrappers.sh` created
- [ ] Generates functions for all agents with `[agent]` section
- [ ] Optional agents wrapped in command -v check
- [ ] Output file sourced from `/etc/profile.d/` in container
- [ ] Functions work in interactive bash
- [ ] Functions work in SSH non-interactive commands

## Notes

- `/etc/profile.d/` is sourced by login shells
- For non-login interactive shells, `.bashrc` sources `/etc/profile.d/` on this image
- `command` builtin prevents function recursion
