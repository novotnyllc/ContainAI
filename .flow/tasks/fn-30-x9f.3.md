## Description

`cai doctor fix container --all` reports `[FIXED]` but SSH still fails with "Permission denied (publickey)". The key injection has **no verification** - it assumes success if `docker exec` returns 0, but the script inside can fail silently.

**Actual error:**
```
[OK] SSH access configured for container containai-xxx
    SSH refresh:                                   [FIXED]

$ cai shell
[ERROR] SSH connection failed: non-transient error
[ERROR]   agent@127.0.0.1: Permission denied (publickey).
```

**Size:** M
**Files:** `src/lib/ssh.sh`, `src/lib/doctor.sh`

## Approach

1. **Add verification to key injection** (`_cai_inject_ssh_key`):
   - After running inject script, verify the key is actually in authorized_keys
   - Run: `docker exec "$container" grep -qF "$key_material" /home/agent/.ssh/authorized_keys`
   - Return failure if verification fails

2. **Add connectivity test to doctor fix**:
   - After "fixing" SSH, do a quick SSH connection test
   - `ssh -o BatchMode=yes -o ConnectTimeout=3 -p $port $host exit 0`
   - If this fails, report `[FAIL]` not `[FIXED]`

3. **Debug the actual failure**:
   - Why is the key not being injected? Possible causes:
     - Script execution through SSH-based docker context mangles arguments
     - The `set -e` in inject script doesn't propagate through `bash -c`
     - Permissions issue on /home/agent/.ssh inside container
   - Add verbose logging to diagnose

## Key context

The inject script is passed as argument to `bash -c`:
```bash
"${docker_cmd[@]}" exec -- "$container_name" bash -c "$inject_script" _ "$pubkey_content"
```

On WSL2 with SSH-based Docker context, this goes through multiple layers:
WSL2 shell -> SSH tunnel -> Docker daemon -> container bash

The `$pubkey_content` could get mangled, or script errors might not propagate.

## Acceptance

- [ ] `cai doctor fix container --all` only reports `[FIXED]` if SSH actually works
- [ ] If key injection fails, clear error message is shown
- [ ] After doctor fix, `cai shell` works (end-to-end test)
- [ ] Verbose mode (`-v`) shows what's actually happening during injection

## Done summary

<!-- flowctl done will append summary here -->

## Evidence

<!-- flowctl done will append evidence here -->
