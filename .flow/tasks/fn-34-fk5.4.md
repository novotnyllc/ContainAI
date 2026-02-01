# fn-34-fk5.4: Implement session detection

## Goal
Create `_cai_detect_sessions()` function with best-effort detection of active SSH connections and terminals.

## Implementation
Add to `src/lib/container.sh`:

```bash
# Session detection function
# Returns: 0 = has sessions, 1 = no sessions, 2 = unknown
_cai_detect_sessions() {
    local container_name="$1"
    local context="${2:-}"

    # Build docker command with context (pattern from _cai_ssh_run)
    local -a docker_cmd=()
    if [[ -n "$context" ]]; then
        docker_cmd=(env DOCKER_CONTEXT= DOCKER_HOST= docker --context "$context")
    else
        docker_cmd=(docker)
    fi

    # Use _cai_timeout wrapper (from docker.sh) and docker exec
    # The script checks for ss availability and returns exit code 2 if missing
    local session_info exit_code
    session_info=$(_cai_timeout 5 "${docker_cmd[@]}" exec "$container_name" sh -c '
        # Check if ss is available
        if ! command -v ss >/dev/null 2>&1; then
            exit 2  # Unknown - ss not available
        fi

        # Count established SSH connections (port 22)
        ssh_count=$(ss -t state established sport = :22 2>/dev/null | tail -n +2 | wc -l)

        # Count PTY devices (active terminals)
        pty_count=$(ls /dev/pts/ 2>/dev/null | grep -c "^[0-9]" || echo 0)

        echo "$ssh_count $pty_count"
    ' 2>/dev/null) && exit_code=$? || exit_code=$?

    # Handle exit codes
    case "$exit_code" in
        0)
            # Success - parse output
            local ssh_count pty_count
            read -r ssh_count pty_count <<< "$session_info"

            if [[ "$ssh_count" -gt 0 || "$pty_count" -gt 1 ]]; then
                return 0  # Has sessions
            fi
            return 1  # No sessions
            ;;
        2)
            # ss not available - unknown
            return 2
            ;;
        *)
            # Timeout or other failure - unknown
            return 2
            ;;
    esac
}
```

## Files
- `src/lib/container.sh`: Add `_cai_detect_sessions` function

## Acceptance
- [ ] Uses `_cai_timeout` wrapper (not raw `timeout`)
- [ ] Uses context-aware docker command
- [ ] Checks for `ss` availability, returns 2 if missing
- [ ] Detects SSH connections via `ss`
- [ ] Detects PTY count via `/dev/pts`
- [ ] Returns 2 (unknown) on timeout/failure
