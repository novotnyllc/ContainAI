# fn-5-urz.7 containai run with safe defaults

## Description
## Overview

Implement `containai run` as a wrapper around `docker sandbox run` with safe defaults.

## Command

```bash
containai run [--agent claude|gemini] [--workspace <path>] [-- <agent args>]
```

## Safe Defaults (FR-4)

- `--credentials=none` (never `host` by default)
- No `--mount-docker-socket`
- No additional volume mounts beyond workspace
- Workspace is current directory if not specified

## Implementation

```bash
containai_run() {
    local agent="${1:-claude}"
    local workspace="${2:-.}"
    
    # Validate workspace exists
    if [[ ! -d "$workspace" ]]; then
        _cai_error "Workspace not found: $workspace"
        return 1
    fi
    
    # Build command
    local cmd=(docker sandbox run)
    cmd+=(--credentials=none)
    cmd+=(--workspace "$workspace")
    cmd+=("$agent")
    
    # Pass through remaining args after --
    shift 2 || true
    if [[ "$1" == "--" ]]; then
        shift
        cmd+=("$@")
    fi
    
    "${cmd[@]}"
}
```

## Config Integration

Load from `.containai/config.toml` or `~/.config/containai/config.toml`:
- `agent` default
- `credentials.mode` (but never override to `host` without explicit flag)

## Error Handling

- Check `containai doctor` status before running
- If no isolation path available, refuse to run with clear message
- If sandbox already exists with different config, warn user to reset

## Reuse

- `aliases.sh:277-347` - `containai()` function has similar structure
## Acceptance
- [ ] Uses `docker sandbox run` (never `docker run`)
- [ ] Default credentials mode is `none`
- [ ] No Docker socket mounted by default
- [ ] Workspace defaults to current directory
- [ ] Respects config file for agent default
- [ ] `-- <args>` passes through to agent
- [ ] Validates workspace exists before running
- [ ] Integrates with doctor check (warns if no isolation)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
