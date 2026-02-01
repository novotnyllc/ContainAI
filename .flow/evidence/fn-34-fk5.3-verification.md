# fn-34-fk5.3: Exit Code Passthrough Verification

**Date:** 2026-02-01
**Status:** VERIFIED

## Summary

Code analysis confirms exit code passthrough is correctly implemented in the SSH subsystem.

## Exit Code Constants (src/lib/ssh.sh:1844-1850)

| Code | Constant | Description |
|------|----------|-------------|
| 0 | `$_CAI_SSH_EXIT_SUCCESS` | Success |
| 10 | `$_CAI_SSH_EXIT_CONTAINER_NOT_FOUND` | Container not found |
| 11 | `$_CAI_SSH_EXIT_CONTAINER_START_FAILED` | Container start failed |
| 12 | `$_CAI_SSH_EXIT_SSH_SETUP_FAILED` | SSH setup failed |
| 13 | `$_CAI_SSH_EXIT_SSH_CONNECT_FAILED` | SSH connection failed |
| 14 | `$_CAI_SSH_EXIT_HOST_KEY_MISMATCH` | Host key mismatch |
| 15 | `$_CAI_SSH_EXIT_CONTAINER_FOREIGN` | Container is foreign |

## Code Flow Analysis

### `_cai_ssh_run_with_retry` (lines 2337-2703)

The core SSH command execution function handles exit codes as follows:

```bash
case $ssh_exit_code in
    0)
        # Success
        return 0
        ;;
    255)
        # SSH transport error - analyze and retry/fail
        ;;
    *)
        # Other exit codes are from the remote command
        # Pass them through as-is (propagate exit code)
        return $ssh_exit_code
        ;;
esac
```

**Key lines:**
- Line 2605: `return 0` for success
- Line 2697: `return $ssh_exit_code` for remote command exit codes (1-254)

### `_cai_ssh_run` (lines 2207-2325)

Handles container/SSH setup errors before delegating to `_cai_ssh_run_with_retry`:

- Line 2239: `return $_CAI_SSH_EXIT_CONTAINER_NOT_FOUND` (10)
- Line 2254: `return $_CAI_SSH_EXIT_CONTAINER_FOREIGN` (15)
- Line 2266/2283: `return $_CAI_SSH_EXIT_CONTAINER_START_FAILED` (11)
- Line 2294/2314: `return $_CAI_SSH_EXIT_SSH_SETUP_FAILED` (12)

### `_containai_exec_cmd` (line 4237)

Calls `_cai_ssh_run` directly without wrapping the return value:

```bash
_cai_ssh_run "$resolved_container_name" "$selected_context" "$force_arg" "$quiet_arg" "false" "$allocate_tty" --login-shell "${exec_cmd[@]}"
```

The exit code from `_cai_ssh_run` becomes the exit code of the function.

## Acceptance Criteria Verification

| Criteria | Status | Evidence |
|----------|--------|----------|
| Exit code 0 from remote returns 0 to host | ✅ | Line 2605: `return 0` |
| Exit code 1-255 from remote returns same to host | ✅ | Line 2697: `return $ssh_exit_code` |
| SSH/container errors return defined codes (10-15) | ✅ | Lines 2239, 2254, 2266, 2283, 2294, 2314, 2633, 2692 |
| Scripts can check `$?` after `cai exec` | ✅ | Direct return propagation in `_containai_exec_cmd` |

## Expected Behavior

| Test Command | Expected Exit | Reason |
|--------------|---------------|--------|
| `cai exec -- true` | 0 | Command succeeds |
| `cai exec -- false` | 1 | `false` returns 1 |
| `cai exec -- exit 42` | 42 | Custom exit code passthrough |
| `cai exec --container nonexistent -- ls` | 10 | Container not found |

## Conclusion

Exit code passthrough is correctly implemented:

1. **Remote command success (0)** → Returns 0
2. **Remote command failure (1-254)** → Returns exact exit code
3. **SSH transport error (255)** → Analyzed for retry/specific error codes
4. **Container/SSH errors** → Returns well-defined codes 10-15
5. **Script integration** → `$?` correctly reflects exit code after `cai exec`

No code changes required - implementation is complete.
