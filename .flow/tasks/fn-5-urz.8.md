# fn-5-urz.8 Context auto-selection (ECI vs Secure Engine)

## Description
## Overview

Enhance `containai run` to automatically select the appropriate Docker context based on isolation availability.

## Logic

```
if ECI enabled:
    use default context (Docker Desktop)
elif Secure Engine context exists:
    use containai-secure context
else:
    warn user, suggest running doctor/install
```

## Implementation

```bash
_cai_select_context() {
    local eci_status
    eci_status=$(_cai_eci_status)
    
    if [[ "$eci_status" == "enabled" ]]; then
        echo ""  # Empty = default context
        return 0
    fi
    
    # Check for Secure Engine context
    if docker context inspect containai-secure >/dev/null 2>&1; then
        echo "containai-secure"
        return 0
    fi
    
    # No isolation available
    return 1
}

containai_run() {
    local context
    if ! context=$(_cai_select_context); then
        _cai_error "No isolation available. Run 'containai doctor' for setup instructions."
        return 1
    fi
    
    local cmd=(docker)
    if [[ -n "$context" ]]; then
        cmd+=(--context "$context")
    fi
    cmd+=(sandbox run ...)
}
```

## Config Override

Allow explicit context in config:
```toml
[secure_engine]
context_name = "containai-secure"  # or custom name
```

## Depends On

<!-- Updated by plan-sync: fn-5-urz.1 confirmed Sysbox context works, but sandbox context is UNKNOWN -->
- Task 1 spike (fn-5-urz.1) findings:
  - **Sysbox context: CONFIRMED** - `docker --context X run --runtime=sysbox-runc` routes correctly
  - **Sandbox context: UNKNOWN** - Spike blocked pending Docker Desktop 4.50+ testing
- If Docker Desktop testing shows sandbox context is ignored, this task needs revision
## Acceptance
- [ ] Auto-selects ECI path when enabled (no context flag)
- [ ] Auto-selects Secure Engine context when ECI not available
- [ ] Warns with actionable message when no isolation available
- [ ] Respects config override for context name
- [ ] Debug output shows which context was selected
- [ ] Works correctly per spike (fn-5-urz.1): Sysbox context confirmed, sandbox context pending Docker Desktop testing
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
