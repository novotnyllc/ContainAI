# fn-1.11 Create check-sandbox.sh for Docker Sandbox and ECI detection

## Description
Create check-sandbox.sh for Docker Sandbox and ECI detection on container startup:

**Docker Sandbox Detection:**
- MUST detect if running via `docker sandbox run` vs plain `docker run`
- **BLOCKS startup** if not in Docker Sandbox (exit with error)
- Research needed: best method to detect sandbox vs plain docker

**ECI Detection:**
- Detect Enhanced Container Isolation status
- **WARNS every time** if ECI disabled (doesn't block)
- Research needed: best method to detect ECI from inside container

**Behavior:**
- Always runs on container startup
- Non-sandbox blocks completely with clear error
- ECI disabled shows warning but allows continue
## Acceptance
- [ ] Detects Docker Sandbox vs plain Docker
- [ ] BLOCKS startup if not in Docker Sandbox
- [ ] Displays clear error message when blocked
- [ ] Detects ECI status
- [ ] WARNS if ECI disabled
- [ ] Warning shows every time (not suppressible)
- [ ] Doesn't block for ECI warning
- [ ] Runs automatically on container startup
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
