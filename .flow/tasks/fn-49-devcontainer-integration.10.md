# fn-49-devcontainer-integration.10 Add no-secrets marker to cai import

## Description

Update `cai import` to create a `.containai-no-secrets` marker file in the data volume when `--no-secrets` flag is used. This marker is required by the devcontainer wrapper to validate that credentials are not exposed.

### Location
`src/lib/import.sh`

### Changes Required

1. **When `--no-secrets` flag is used**:
   - Create `.containai-no-secrets` marker file in the volume root (`/mnt/agent-data/.containai-no-secrets`)
   - Marker content: timestamp and flag indicator (e.g., `created: 2024-01-01T00:00:00Z`)

2. **When full import (with secrets)**:
   - Remove `.containai-no-secrets` marker if it exists
   - This ensures the marker accurately reflects the volume's credential state

3. **Marker format**:
   ```
   # ContainAI no-secrets marker
   # This volume was created with: cai import --no-secrets
   # Credential files are NOT synced to this volume
   created: 2024-01-01T00:00:00Z
   ```

### Why This Is Needed

The devcontainer wrapper validates volumes before mounting when `enableCredentials=false`:
- If marker exists: Volume is safe, mount it
- If marker missing: Volume may contain credentials, refuse to mount and prompt user

This defense-in-depth prevents untrusted code from accessing credentials even if the init.sh symlink filtering is bypassed.

### Implementation

```bash
# In _cai_import_to_volume() or similar:

# At end of import process:
if [[ "$NO_SECRETS" == "true" ]]; then
    # Create no-secrets marker
    cat > "$VOLUME_ROOT/.containai-no-secrets" << EOF
# ContainAI no-secrets marker
# This volume was created with: cai import --no-secrets
# Credential files are NOT synced to this volume
created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
else
    # Remove marker if doing full import
    rm -f "$VOLUME_ROOT/.containai-no-secrets"
fi
```

## Acceptance

- [ ] `cai import --no-secrets` creates `.containai-no-secrets` marker in volume root
- [ ] `cai import` (without --no-secrets) removes the marker if it exists
- [ ] Marker file contains human-readable explanation and timestamp
- [ ] Existing tests pass
- [ ] New test verifies marker creation/removal

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
