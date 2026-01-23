# fn-10-vep.36 Add kernel version check for sysbox compatibility

## Description
Add kernel version checking to `cai doctor` and `cai setup` using portable bash (no bc dependency). Sysbox requires kernel 5.5+ for its user namespace and syscall interception features.

**Size:** S
**Files:** `src/lib/doctor.sh`, `src/lib/setup.sh`

## Why Kernel Checks?

Sysbox provides automatic user namespace mapping and secure DinD, but it requires kernel 5.5+ for:
- User namespace support
- Syscall interception (procfs/sysfs virtualization)
- Secure container isolation

Note: **Sysbox handles all userns mapping automatically** via /etc/subuid and /etc/subgid. No manual configuration needed. We just need to ensure the kernel supports sysbox.

## Approach

1. Create `_cai_check_kernel_for_sysbox()` helper:
   - Parse kernel version from `uname -r`
   - Handle WSL2 format: `5.15.133.1-microsoft-standard-WSL2`
   - Check >= 5.5 for Sysbox support
   - Use bash arithmetic (no bc dependency)

2. Implementation pattern:
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

     return 0
   }
   ```

3. In `cai doctor`:
   - Show kernel version
   - Warn if < 5.5: "Sysbox requires kernel 5.5+"

4. In `cai setup`:
   - Block setup if kernel < 5.5

## Key context

- Sysbox minimum: kernel 5.5 (released March 2020)
- Most modern distros (Ubuntu 22.04+, Debian 12+) have 5.15+
- WSL2 kernel is typically 5.15+ (updated via Windows Update)
- WSL2 kernels have format: 5.15.133.1-microsoft-standard-WSL2
- cut -d. -f2 gets "15" correctly even with multiple dots
- bc may not be installed on minimal systems

## Acceptance
- [ ] `cai doctor` displays kernel version
- [ ] Kernel < 5.5 shows error about Sysbox compatibility
- [ ] `cai setup` blocks installation on kernel < 5.5
- [ ] Handles WSL2 kernel format (5.15.133.1-microsoft-standard-WSL2)
- [ ] No bc dependency - uses bash arithmetic
- [ ] Gracefully handles unparseable kernel versions (warn, don't fail)
## Done summary
Added kernel version check for Sysbox compatibility (requires 5.5+). Updated cai doctor to display kernel version and incorporate it into isolation status. Updated cai setup to block installation on incompatible kernels with helpful upgrade instructions.
## Evidence
- Commits: a8dfec1, 60a39e7
- Tests: bash -c 'source src/containai.sh && _cai_check_kernel_for_sysbox', bash -c 'source src/containai.sh && _cai_doctor', bash -c 'source src/containai.sh && _cai_doctor_json', bash -c 'source src/containai.sh && _cai_setup --dry-run'
- PRs:
