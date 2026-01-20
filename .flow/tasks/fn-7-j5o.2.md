# fn-7-j5o.2 Create SECURITY.md

## Description
Create SECURITY.md to establish trust for a security-critical sandboxing tool. Document the security model, supported versions, and vulnerability reporting process.

**Size:** S
**Files:** `SECURITY.md`

## Approach

- Follow GitHub's security policy best practices
- Include threat model summary (what ContainAI protects against)
- Document supported versions table
- Provide clear vulnerability reporting process (private, not via public issues)
- Include safe harbor statement for security researchers
- Summarize security architecture (ECI/Sysbox isolation)

## Key Context

- ECI = Enhanced Container Isolation (Docker Desktop 4.50+)
- Sysbox = Nestybox runtime for nested containers
- Security implementation in `agent-sandbox/lib/eci.sh` and `lib/docker.sh`
- FR-4 decision: reject dangerous options rather than gate behind flags
## Acceptance
- [ ] SECURITY.md exists at project root
- [ ] Includes supported versions table
- [ ] Documents vulnerability reporting process (email, not public issues)
- [ ] Includes safe harbor statement
- [ ] Summarizes security model (ECI vs Sysbox isolation)
- [ ] Explains what threats ContainAI does/doesn't protect against
- [ ] Links to detailed security info in agent-sandbox/README.md
- [ ] Renders correctly on GitHub
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
