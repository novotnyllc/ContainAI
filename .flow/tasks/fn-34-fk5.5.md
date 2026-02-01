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
- [x] Warns when sessions detected (interactive prompt)
- [x] `--force` flag skips warning
- [x] Non-interactive mode proceeds without prompt
- [x] "Unknown" session state (return 2) proceeds without warning

## Done summary
## Summary

Added session warning to `cai stop` command that prompts users before stopping containers with active SSH sessions or terminals.

### Changes

- Added `--force` flag to `_containai_stop_cmd` to skip session warning prompt
- Added session detection before stop/remove in two locations:
  1. When using `--container <name>` to stop a specific container
  2. When stopping via workspace state (auto-resolved container)
- Updated `_containai_stop_help` to document `--force` flag and session warning behavior

### Implementation Details

- Calls `_cai_detect_sessions` before stopping if:
  - `--force` is NOT set
  - stdin is a terminal (`-t 0`)
- Session detection return codes:
  - 0 = has sessions → prompt for confirmation
  - 1 = no sessions → proceed silently
  - 2 = unknown (ss unavailable) → proceed silently
- Prompt format: `"Stop anyway? [y/N]: "` (defaults to No)

### Files Changed

- `src/containai.sh`: `_containai_stop_cmd` function and `_containai_stop_help`
## Evidence
- Commits:
- Tests:
- PRs:
