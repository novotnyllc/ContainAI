# fn-10-vep.34 Add security flags to container run (no-new-privileges, cap-drop)

## Description
Configure security defaults for all container runs. Docker applies MaskedPaths/ReadonlyPaths by default - our job is to NOT disable them and validate they're applied.

**Size:** S  
**Files:** `src/lib/container.sh`

## Approach

1. **Ensure we never disable security defaults**:
   - NO `--security-opt systempaths=unconfined` 
   - NO `--privileged` flag

2. **Defer aggressive hardening** (document as future work):
   - `--security-opt=no-new-privileges` - conflicts with entrypoint sudo
   - `--cap-drop=ALL` - needs baseline testing first

3. **Add validation helper** for use in tests:
   ```bash
   _cai_validate_masked_paths() {
     # Validate via mount metadata, not by expecting cat to fail
     grep "/proc/kcore" /proc/self/mountinfo 2>/dev/null || \
       findmnt -T /proc/kcore >/dev/null 2>&1
   }
   ```

4. Document in code comments what Docker defaults provide

## Key context

- MaskedPaths are bind-mounted from /dev/null (cat may succeed with empty output)
- ReadonlyPaths are mounted read-only
- Docker applies these by default; Sysbox respects them
- No CLI API to add these per-container (only to disable via systempaths=unconfined)
- Validation should use mount metadata, not exit codes
## Approach

1. Add security flags to `_containai_run()` Sysbox path:
   - `--security-opt=no-new-privileges` - prevent privilege escalation via setuid binaries
   - `--cap-drop=ALL` - drop all capabilities
   - `--cap-add=CHOWN,DAC_OVERRIDE,FOWNER,SETGID,SETUID,NET_BIND_SERVICE` - add minimal required

2. MaskedPaths and ReadonlyPaths:
   - Docker applies these by default, Sysbox respects them
   - Verify defaults are applied (no explicit flags needed unless overridden)
   - Document the paths in code comments for clarity

3. Create `_containai_security_flags()` helper function that returns the security arguments

## Key context

**MaskedPaths** (hidden from container - Docker default):
- /proc/acpi, /proc/asound, /proc/interrupts, /proc/kcore, /proc/keys
- /proc/latency_stats, /proc/sched_debug, /proc/scsi, /proc/timer_list, /proc/timer_stats
- /sys/devices/virtual/powercap, /sys/firmware

**ReadonlyPaths** (read-only in container - Docker default):
- /proc/bus, /proc/fs, /proc/irq, /proc/sys, /proc/sysrq-trigger

**Minimal capabilities** needed for typical dev container:
- CHOWN - change file ownership
- DAC_OVERRIDE - bypass file permission checks (needed for sudo)
- FOWNER - bypass ownership checks
- SETGID/SETUID - change process identity
- NET_BIND_SERVICE - bind to privileged ports <1024
## Acceptance
- [ ] NO `--security-opt systempaths=unconfined` in container creation
- [ ] NO `--privileged` flag in container creation
- [ ] `--security-opt=no-new-privileges` NOT added (deferred - breaks sudo)
- [ ] Aggressive cap-drop NOT added (deferred - needs testing)
- [ ] Validation helper uses mount metadata (not cat exit code)
- [ ] Code comments document Docker's default MaskedPaths/ReadonlyPaths
- [ ] Future hardening documented as out-of-scope enhancement
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
