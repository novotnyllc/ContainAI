# fn-5-urz.14 containai sandbox clear-credentials command

## Description
## Overview

Implement `containai sandbox clear-credentials` to remove sandbox credential volumes when needed for troubleshooting.

## Background

Per Docker troubleshooting docs, credential issues may require clearing the sandbox credential storage. This is separate from `sandbox reset` which removes the container but may leave volumes.

## Command

```bash
containai sandbox clear-credentials [--workspace <path>] [--agent claude|gemini]
```

## What It Does

1. Identify credential volume for the sandbox/agent
2. Warn user about data loss
3. Remove the credential volume
4. Confirm removal

## Implementation

```bash
containai_sandbox_clear_credentials() {
    local workspace="${1:-.}"
    local agent="${2:-claude}"

    workspace=$(realpath "$workspace")

    # Credential volume naming convention (agent-specific)
    # This may need investigation - Docker docs don't specify exact names
    local volume_name="sandbox-${agent}-credentials"

    _cai_warn "This will remove stored credentials for $agent in $workspace"
    _cai_warn "You may need to re-authenticate after this operation"

    # Check if volume exists
    if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
        _cai_info "No credential volume found: $volume_name"
        return 0
    fi

    # Remove volume
    docker volume rm "$volume_name"
    _cai_info "[OK] Credential volume removed"
}
```

## Edge Cases

- Volume in use by running sandbox: refuse with message
- Volume doesn't exist: no error, info message
- Multiple agents with different volumes

## References

- Docker troubleshooting: https://docs.docker.com/ai/sandboxes/troubleshooting/
- May need to inspect actual volume names created by Docker Sandboxes
## Acceptance
- [ ] Identifies correct credential volume for agent
- [ ] Warns user before removing
- [ ] Handles volume not found gracefully
- [ ] Refuses if volume in use (sandbox running)
- [ ] Works for different agents (claude, gemini)
- [ ] Confirms successful removal
## Done summary
Implemented `cai sandbox clear-credentials` command to remove Docker sandbox credential volumes for troubleshooting authentication issues. The command identifies the correct volume per agent (docker-<agent>-sandbox-data), warns about data loss, refuses if any containers reference the volume, and verifies removal.
## Evidence
- Commits: 46d40f3, 7951791, 197c6e1, 75354c5
- Tests: bash -n containai.sh, cai sandbox --help, cai sandbox clear-credentials --help, cai sandbox clear-credentials --agent unknown, cai sandbox clear-credentials --workspace /tmp
- PRs:
