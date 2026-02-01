# fn-34-fk5.3: Verify exit code passthrough

## Goal
Verify remote command exit codes are properly returned to the caller.

## Exit Codes (from src/lib/ssh.sh:1844-1850)
- 0: Success (`$_CAI_SSH_EXIT_SUCCESS`)
- 10: Container not found (`$_CAI_SSH_EXIT_CONTAINER_NOT_FOUND`)
- 11: Container start failed (`$_CAI_SSH_EXIT_CONTAINER_START_FAILED`)
- 12: SSH setup failed (`$_CAI_SSH_EXIT_SSH_SETUP_FAILED`)
- 13: SSH connection failed (`$_CAI_SSH_EXIT_SSH_CONNECT_FAILED`)
- 14: Host key mismatch (`$_CAI_SSH_EXIT_HOST_KEY_MISMATCH`)
- 15: Container is foreign (`$_CAI_SSH_EXIT_CONTAINER_FOREIGN`)
- 1-255: Passthrough from remote command

## Verification Steps
1. Test success: `cai exec -- true; echo $?` → 0
2. Test failure: `cai exec -- false; echo $?` → 1
3. Test custom code: `cai exec -- exit 42; echo $?` → 42
4. Test container not found: `cai exec --container nonexistent -- ls; echo $?` → 10

## Files
- `src/lib/ssh.sh`: Exit code handling

## Acceptance
- [ ] Exit code 0 from remote returns 0 to host
- [ ] Exit code 1-255 from remote returns same to host
- [ ] SSH/container errors return defined codes (10-15)
- [ ] Scripts can check `$?` after `cai exec`
