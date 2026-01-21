# fn-10-vep.33 Deprecate ECI detection (lib/eci.sh) - keep for diagnostics only

## Description
Deprecate the ECI detection logic in `lib/eci.sh`. Keep the file for diagnostic purposes only - it should no longer be used in the main container creation flow.

**Size:** S  
**Files:** `src/lib/eci.sh`, `src/lib/doctor.sh`

## Approach

1. Add deprecation banner to top of `lib/eci.sh`
2. Remove ECI checks from main flow (already done by fn-10-vep.32)
3. Keep ECI detection functions for `cai doctor` diagnostics only
4. Update `cai doctor` to show ECI status as "informational" not "required"
5. Add note: "ECI detected but not used - ContainAI uses Sysbox for isolation"
## Acceptance
- [ ] `lib/eci.sh` has deprecation comment at top
- [ ] ECI functions not called in container creation flow
- [ ] `cai doctor` shows ECI as informational (not blocking if unavailable)
- [ ] Doctor output indicates Sysbox is used regardless of ECI availability
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
