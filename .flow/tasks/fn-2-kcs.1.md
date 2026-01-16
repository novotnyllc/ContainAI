# fn-2-kcs.1 PR1: Aliases.sh cleanup and label fix

## Description
Clean up aliases.sh with consistent naming, fix label propagation, and improve ECI output.

## Changes Required

### Naming Cleanup
- Rename all `_CSD_` prefixed variables to `_ASB_`
- Update all comments that reference "csd" to "asb"
- Change "Dotnet sandbox" messages to "Agent Sandbox" (title case)
- Remove unused `_CSD_MOUNT_ONLY_VOLUMES` array

### Label Fix
- Add `--label` flag to `docker sandbox run` command
- Use OCI standard labels: `org.opencontainers.image.source`, `org.opencontainers.image.created`
- The label `asb.sandbox=agent-sandbox` should be added for ownership tracking

### ECI Output Simplification
- Change multi-line ECI output to single-line status
- Show: "ECI: enabled" or "ECI: not detected (userns/rootless provides isolation)"
- Add `ASB_REQUIRE_ECI=1` environment variable to enforce ECI

### Isolation Warning
- If neither ECI nor userns/rootless detected, show strong warning
- Warning should be prominent but not blocking (fail-open)
- Warn about running without isolation but proceed

## Files to Modify
- `agent-sandbox/aliases.sh`
## Acceptance
- [ ] All `_CSD_` variables renamed to `_ASB_`
- [ ] All "csd" references in comments updated to "asb"
- [ ] "Dotnet sandbox" changed to "Agent Sandbox" in output messages
- [ ] `_CSD_MOUNT_ONLY_VOLUMES` array removed
- [ ] `docker sandbox run` includes `--label` flags with OCI standard labels
- [ ] ECI check shows one-line status by default
- [ ] `ASB_REQUIRE_ECI=1` environment variable supported
- [ ] Strong warning shown if no isolation detected (but doesn't block)
- [ ] `source aliases.sh && asb --help` works correctly
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
