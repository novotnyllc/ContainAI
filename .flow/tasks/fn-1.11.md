# fn-1.11 Implement sandbox detection in csd wrapper

## Description
Implement sandbox and ECI detection logic in the `csd` wrapper script (NOT in container entrypoint).

**Key Design Decision (per spec):**
- Detection and enforcement happens in `csd` wrapper BEFORE container start
- Plain `docker run` is allowed for smoke tests (no entrypoint blocking)
- Detection is best-effort, but blocks on known "no" state

**Docker Sandbox Detection:**
```bash
# Sandbox availability check
if docker sandbox ls >/dev/null 2>&1; then
  SANDBOX="yes"
elif ! command -v docker >/dev/null 2>&1; then
  SANDBOX="no"  # No docker at all
elif docker sandbox --help 2>&1 | grep -q "not recognized\|unknown command"; then
  SANDBOX="no"  # Docker exists but sandbox not supported
else
  SANDBOX="no"  # Sandbox command failed for other reason
fi
```

**ECI Detection:**
- Best-effort detection using `docker info --format '{{.SecurityOptions}}'`
- Look for userns/rootless hints
- Detection result: `eci=yes/no/unknown`
- **WARNS** if ECI disabled or unknown (doesn't block)

**Blocking Policy:**
- Block if `SANDBOX="no"` with clear **actionable** message:
  - Minimum Docker Desktop version required
  - How to enable sandbox feature
  - Link to documentation
- Do NOT block on "unknown" (fail-open for edge cases)

**Behavior:**
- `csd` performs detection BEFORE starting container
- Blocks with actionable message if sandbox definitely unavailable
- Warns but proceeds if ECI detection returns no/unknown
- Clear messaging for all states

## Acceptance
- [ ] `csd` checks for docker sandbox availability before starting
- [ ] BLOCKS with actionable error if `sandbox=no` (includes version requirements)
- [ ] Does NOT block on "unknown" states (fail-open)
- [ ] WARNS if ECI detection returns no/unknown
- [ ] Clear messaging explains each state and next steps
- [ ] Detection code is in `csd` wrapper (aliases.sh)
- [ ] Plain `docker run` works without blocking (no entrypoint check)
- [ ] Detection is documented in README

## Done summary
## What changed
- Added `_csd_check_eci()` function for best-effort ECI detection via `docker info`
- Added ECI check call in `csd()` function after sandbox availability check
- Updated README.md with ECI Detection section documenting behavior

## Why
- Task spec requires ECI detection with warnings for transparency
- Best-effort detection helps users know if enhanced isolation is active
- Non-blocking design ensures sandbox usability regardless of ECI status

## Verification
- `bash -n aliases.sh` - syntax check passed
- Manual review of detection logic and warning messages
- README documentation updated to reflect implementation

## Follow-ups
- Could add verbose mode flag to show detailed detection results
## Evidence
- Commits: 25d3373e63a746a4a9c70b20aa6002d23a44a600
- Tests: bash -n aliases.sh
- PRs: