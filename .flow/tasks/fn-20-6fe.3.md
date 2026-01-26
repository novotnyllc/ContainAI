# fn-20-6fe.3 Write PRD-B: Sysbox host-side fix options

## Description

Write PRD-B: A Product Requirements Document for the proper fix options. This is a specification document only - no implementation.

**Size:** S
**Files:**
- `.flow/specs/prd-sysbox-dind-fix.md` (new file)

## Approach

Write a comprehensive PRD covering:

1. **Executive Summary**
   - Problem statement
   - Available fix options with clear ownership boundaries by deployment mode
   - Recommended approach

2. **Technical Analysis**
   - Reference fn-20-6fe-technical-analysis.md for details
   - How sysbox-fs virtualizes /proc (bind mounts FUSE over procfs)
   - How runc's security check works (openat2 + RESOLVE_NO_XDEV)
   - Why the conflict occurs (cross-device detection)
   - Specific commit SHAs from technical analysis

3. **Ownership Boundary Clarification by Deployment Mode**
   - **Linux Sysbox Mode**:
     - Operator-controlled: sysbox-fs, sysbox-runc upgrade
     - ContainAI-controlled: containerd.io pin, Dockerfile
   - **Docker Desktop ECI Mode**:
     - Docker Inc-controlled: Sysbox components bundled in Docker Desktop
     - Operator cannot independently upgrade sysbox
     - ContainAI-controlled: containerd.io pin, Dockerfile
   - Which options ContainAI can ship vs which require operator/vendor action

4. **Fix Options Evaluated**

   **Option A: Wait for Sysbox Release** (varies by deployment mode)
   - **Linux Sysbox Mode**: Operator upgrades sysbox when release is available
     - Pros: No effort, officially supported
     - Cons: Unknown timeline, dependency on upstream
     - Version gate: Sysbox release containing fix commits (SHAs from Task 1)
     - Action: Track sysbox releases, document minimum version
   - **Docker Desktop ECI Mode**: Wait for Docker Desktop update
     - Pros: No operator effort
     - Cons: Depends on Docker Inc release cadence, no direct control
     - Action: Track Docker Desktop releases
   - Hypothesis status: Treat version numbers as hypotheses until confirmed

   **Option B: Build Sysbox from Source** (Linux Sysbox Mode only)
   - Pros: Immediate fix, proven code
   - Cons: Maintenance burden, not released, supply-chain risk
   - Required commits: [specific SHAs from technical analysis]
   - Risk: Untested, potential regressions
   - Not applicable to ECI Mode

   **Option C: Contribute Fix Upstream** (community action)
   - Pros: Benefits community
   - Cons: Time to contribute and merge
   - Scope: What testing/documentation would be required?

   **Option D: Alternative Workarounds**
   - AppArmor profile (different error variant - LXC/Proxmox only, not sysbox)
   - Configure inner Docker to avoid requesting the sysctl (based on Task 1 sysctl source analysis)
     - If sysbox injects the sysctl: document sysbox configuration option if available
     - If moby/containerd defaults: document how to override
   - Sysbox configuration options (if any exist)

5. **Recommendation**
   - Primary: [based on analysis, respecting ownership boundaries by deployment mode]
   - Secondary: [fallback option]
   - Use PRD-A workaround in the meantime
   - Differentiate recommendations for Linux Sysbox vs Docker Desktop ECI users

6. **Future Implementation Scope** (for implementation epic)
   - What would be done for each option
   - Testing requirements
   - Documentation updates

## Key context

- This PRD is for long-term solutions
- Based on analysis from Task 1 (technical analysis document)
- Clearly separate ContainAI-controllable vs operator-controllable vs vendor-controllable options
- Seccomp interception fix is host-side (operator must upgrade sysbox in Linux mode)
- **ECI support status**: Consume Task 1's "ECI Support Status" section as input - do NOT pre-assume; if deprecated, discuss ECI as external ecosystem context only
- Treat version predictions as hypotheses

## Acceptance

- [ ] PRD-B created at `.flow/specs/prd-sysbox-dind-fix.md`
- [ ] Technical analysis references technical analysis document with commit SHAs
- [ ] Ownership boundary clearly documented by deployment mode (Linux Sysbox vs Docker Desktop ECI)
- [ ] All fix options evaluated with pros/cons and ownership assignment
- [ ] Option A includes specific version gate (commits, not predicted version numbers) + ECI mode considerations
- [ ] Option B includes specific commit SHAs and supply-chain risk (Linux mode only)
- [ ] Option D evaluated based on sysctl OCI spec source analysis from Task 1
- [ ] Clear recommendation with rationale respecting ownership boundaries by deployment mode
- [ ] No implementation performed - PRD only

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
