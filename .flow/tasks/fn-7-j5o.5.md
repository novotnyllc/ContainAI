# fn-7-j5o.5 Create troubleshooting guide

## Description
Create an expanded troubleshooting guide covering 20+ common error scenarios, organized by symptom (what user sees) rather than cause.

**Size:** M
**Files:** `docs/troubleshooting.md`

## Approach

- Organize by symptom (error message or observed behavior)
- Include verbatim error messages for searchability
- Provide diagnostic commands to gather info
- Link to related GitHub issues where applicable
- Include `cai doctor` output interpretation

## Key Context

- Current troubleshooting is only 4 scenarios in `agent-sandbox/README.md:259-280`
- `cai doctor` runs system capability checks
- Common issues: Docker context mismatch, ECI not available, Sysbox not installed
- Platform differences: Linux vs WSL2 vs macOS
- Credential sync via `cai import`, clear via `cai sandbox clear-credentials`
## Acceptance
- [ ] docs/troubleshooting.md exists
- [ ] Organized by symptom/error message, not by cause
- [ ] Includes 20+ documented scenarios
- [ ] Error messages are verbatim and searchable
- [ ] Each scenario has: Symptom → Diagnosis → Solution
- [ ] Documents `cai doctor` output interpretation
- [ ] Covers platform-specific issues (Linux, WSL2, macOS)
- [ ] Covers ECI vs Sysbox mode issues
- [ ] Covers credential/sync issues
- [ ] Includes "Still stuck?" section with support channels
## Done summary
Created comprehensive troubleshooting guide with 48+ documented error scenarios, organized by symptom with Symptom->Diagnosis->Solution pattern for each issue.
## Evidence
- Commits: ac3f93a, edadb9f, a65861f, 1fd1eb3
- Tests: grep -c '^### ' docs/troubleshooting.md
- PRs: