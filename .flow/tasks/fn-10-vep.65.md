# fn-10-vep.65 Create docs/troubleshooting.md

## Description
Create comprehensive troubleshooting documentation covering SSH issues, container problems, and common errors.

**Size:** M
**Files:** docs/troubleshooting.md

## Approach

1. Structure by symptom (not cause):
   - "SSH connection refused"
   - "Container won't start"
   - "Permission denied"
   - "Port already in use"
   - "Host key verification failed"

2. For each issue:
   - Symptoms
   - Diagnostic commands
   - Likely causes
   - Resolution steps

3. Include:
   - `cai doctor` output interpretation
   - Common SSH debugging (`ssh -vv`)
   - Container log inspection
   - Port conflict resolution
   - SSH config verification

4. Quick reference section at top with most common fixes

## Key context

- Users may not understand SSH internals
- Provide copy-paste commands
- Link to relevant config files
- Show expected vs actual output
## Acceptance
- [ ] docs/troubleshooting.md created
- [ ] Covers SSH connection issues
- [ ] Covers container startup issues
- [ ] Covers permission issues
- [ ] Covers port conflicts
- [ ] Quick reference section at top
- [ ] Copy-paste diagnostic commands
- [ ] Clear resolution steps
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
