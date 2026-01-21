# fn-10-vep.55 Update cai doctor to validate SSH setup and connectivity

## Description
Update `cai doctor` to validate SSH setup and connectivity.

**Size:** M
**Files:** lib/doctor.sh

## Approach

1. Add SSH checks to `_cai_doctor()`:
   - Check `~/.config/containai/id_containai` exists
   - Check `~/.ssh/containai.d/` exists
   - Check Include directive in `~/.ssh/config`
   - Check OpenSSH version >= 7.3p1

2. Add connectivity test (optional, if container running):
   - Try `ssh -o BatchMode=yes -o ConnectTimeout=5 {container}`
   - Report success/failure with helpful message

3. Clear remediation messages:
   - "Run 'cai setup' to configure SSH"
   - "OpenSSH 7.3p1+ required for Include directive"

## Key context

- doctor should be fast - connectivity test only if container exists
- Use -o BatchMode=yes to prevent password prompts
- ConnectTimeout=5 to fail fast
## Acceptance
- [ ] SSH key existence checked
- [ ] SSH config.d directory checked
- [ ] Include directive in ~/.ssh/config checked
- [ ] OpenSSH version checked (7.3p1+)
- [ ] Connectivity test for running containers
- [ ] Clear error messages with remediation steps
- [ ] `cai doctor` exits 0 when all checks pass
- [ ] `cai doctor` exits non-zero with details when checks fail
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
