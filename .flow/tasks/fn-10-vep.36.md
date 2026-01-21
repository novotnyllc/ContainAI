# fn-10-vep.36 Add kernel version check for ID-mapped mounts

## Description
Add kernel version checking to `cai doctor` and `cai setup` using portable bash (no bc dependency). Handle WSL2 kernel version format.

**Size:** S  
**Files:** `src/lib/doctor.sh`, `src/lib/setup.sh`

## Approach

1. Create `_cai_check_kernel_version()` helper:
   - Parse kernel version robustly (handles `5.15.133.1-microsoft-standard-WSL2`)
   - Extract major/minor as integers
   - Compare using bash arithmetic (no bc)

2. Implementation:
   ```bash
   _cai_check_kernel_for_sysbox() {
     local kernel_version major minor
     kernel_version=$(uname -r)
     
     major=$(echo "$kernel_version" | cut -d. -f1)
     minor=$(echo "$kernel_version" | cut -d. -f2)
     
     # Validate we got numbers
     if ! [[ "$major" =~ ^[0-9]+$ ]] || ! [[ "$minor" =~ ^[0-9]+$ ]]; then
       _cai_warn "Could not parse kernel version: $kernel_version"
       return 0  # Don't block, just warn
     fi
     
     # Sysbox requires 5.5+
     if [[ "$major" -lt 5 ]] || { [[ "$major" -eq 5 ]] && [[ "$minor" -lt 5 ]]; }; then
       _cai_error "Kernel $major.$minor too old. Sysbox requires 5.5+"
       return 1
     fi
     
     # ID-mapped mounts require 5.12+
     if [[ "$major" -lt 5 ]] || { [[ "$major" -eq 5 ]] && [[ "$minor" -lt 12 ]]; }; then
       _cai_warn "Kernel $major.$minor: ID-mapped mounts unavailable."
     fi
     
     return 0
   }
   ```

## Key context

- WSL2 kernels have format: 5.15.133.1-microsoft-standard-WSL2
- cut -d. -f2 gets "15" correctly even with multiple dots
- bc may not be installed on minimal systems
- Bash arithmetic is sufficient for version comparison
## Approach

1. Create `_cai_check_kernel_version()` helper:
   - Parse kernel version from `uname -r`
   - Check >= 5.5 for Sysbox support
   - Check >= 5.12 for ID-mapped mounts (seamless UID mapping)

2. In `cai doctor`:
   - Show kernel version
   - Warn if < 5.5: "Sysbox requires kernel 5.5+"
   - Warn if < 5.12: "ID-mapped mounts unavailable, files may have wrong ownership"

3. In `cai setup`:
   - Block setup if kernel < 5.5
   - Warn but continue if kernel < 5.12

## Key context

- Sysbox minimum: kernel 5.5 (released March 2020)
- ID-mapped mounts: kernel 5.12 (released April 2021)
- Most modern distros (Ubuntu 22.04+, Debian 12+) have 5.15+
- WSL2 kernel is typically 5.15+ (updated via Windows Update)
## Acceptance
- [ ] `cai doctor` displays kernel version
- [ ] Kernel < 5.5 shows error about Sysbox compatibility
- [ ] Kernel < 5.12 shows warning about ID-mapped mounts
- [ ] `cai setup` blocks installation on kernel < 5.5
- [ ] Handles WSL2 kernel format (5.15.133.1-microsoft-standard-WSL2)
- [ ] No bc dependency - uses bash arithmetic
- [ ] Gracefully handles unparseable kernel versions (warn, don't fail)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
