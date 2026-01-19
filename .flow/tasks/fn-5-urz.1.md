# fn-5-urz.1 Spike: Validate docker sandbox + context interaction

## Description
## Overview

Validate whether `docker sandbox run` respects Docker context selection (`--context` flag or `DOCKER_CONTEXT` env var). This is a **blocking spike** - if sandboxes ignore context, the Secure Engine architecture is invalid.

## What to Test

1. Create a test Docker context pointing to an alternate endpoint (or mock)
2. Run `docker --context <test-context> sandbox run claude` 
3. Observe which Docker daemon receives the request
4. Test with `DOCKER_CONTEXT=<test-context> docker sandbox run claude`

## Expected Outcomes

- **Context works**: Proceed with Secure Engine tasks (fn-5-urz.10, fn-5-urz.11)
- **Context ignored**: Document limitation, revise PRD to ECI-only path for isolation

## Reuse

- None (greenfield spike)

## References

- PRD open question #1: `.flow/specs/sysbox.md` line ~390
- Docker contexts: https://docs.docker.com/engine/manage-resources/contexts/
## Acceptance
- [ ] Spike document created with test methodology
- [ ] Tests executed on Docker Desktop 4.50+ with sandboxes enabled
- [ ] Results documented: context respected (yes/no)
- [ ] If no: PRD updated with ECI-only fallback recommendation
- [ ] Epic fn-5-urz updated with findings
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
