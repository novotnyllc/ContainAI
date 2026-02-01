# fn-34-fk5.5: Add session warning to cai stop

## Goal
Integrate session detection into stop command to warn users before stopping containers with active sessions.

## Implementation
In `_containai_stop_cmd` (src/containai.sh):

1. Add `--force` flag parsing
2. Before stopping, call `_cai_detect_sessions`
3. Prompt if sessions detected and interactive

```bash
# Add to flag parsing:
--force) force_flag=true ;;

# Before actual stop:
if [[ "$force_flag" != "true" ]] && [[ -t 0 ]]; then
    local session_result
    _cai_detect_sessions "$container_name" "$context" && session_result=$? || session_result=$?
    if [[ "$session_result" -eq 0 ]]; then
        _cai_warn "Container may have active sessions"
        read -rp "Stop anyway? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy] ]] || return 1
    fi
    # session_result 1 = no sessions, 2 = unknown: proceed
fi
```

## Files
- `src/containai.sh`: `_containai_stop_cmd` function

## Acceptance
- [ ] Warns when sessions detected (interactive prompt)
- [ ] `--force` flag skips warning
- [ ] Non-interactive mode proceeds without prompt
- [ ] "Unknown" session state (return 2) proceeds without warning
