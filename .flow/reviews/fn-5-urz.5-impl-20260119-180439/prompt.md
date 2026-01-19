# Implementation Review: fn-5-urz.5 - ECI detection (uid_map + runtime check)

## Task Spec

Implement ECI (Enhanced Container Isolation) detection per Docker documentation methods.

### Functions Required:
- `_cai_eci_available()` - Check if Docker Business with ECI is available
- `_cai_eci_enabled()` - Two validation methods: uid_map check and runtime check
- `_cai_eci_status()` - Returns: "enabled", "available_not_enabled", "not_available"

### Acceptance Criteria:
- [ ] uid_map check correctly parses isolation status
- [ ] Runtime check verifies sysbox-runc vs runc
- [ ] Both methods must agree for "enabled" status
- [ ] Ephemeral containers are cleaned up (no leak)
- [ ] Timeout handling if Docker hangs
- [ ] Clear status messages: "ECI enabled", "ECI available but not enabled", "ECI not available"

## Changes Summary

This implementation adds ECI detection to the ContainAI library.

**Files changed:**
- `agent-sandbox/lib/eci.sh` (NEW) - ECI detection library
- `agent-sandbox/containai.sh` - Integration of eci.sh

## Review Instructions

Please review as John Carmack would - focus on:
1. Correctness of the uid_map parsing logic
2. Runtime check implementation and container cleanup
3. Error handling and timeout coverage
4. Code quality and bash best practices
5. Whether acceptance criteria are met

## Verdict Format

Respond with ONE of:
- **SHIP** - Implementation is correct and complete
- **NEEDS_WORK** - Minor issues to fix (list them)
- **MAJOR_RETHINK** - Fundamental issues requiring redesign
