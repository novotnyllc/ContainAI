# fn-20-6fe.2 Write PRD-A: Temporary runc downgrade workaround

## Description

Write PRD-A: A Product Requirements Document for the temporary containerd.io/runc downgrade workaround. This is a specification document only - no implementation.

**Size:** S
**Files:**
- `.flow/specs/prd-runc-downgrade-workaround.md` (new file)

## Approach

Write a comprehensive PRD covering:

1. **Executive Summary**
   - Problem statement
   - Proposed temporary solution (image-side containerd.io pin)
   - Time-boxed nature of workaround
   - Explicit scope: ContainAI-controlled changes only
   - **Applicability decision tree** (from Task 1 step 4):
     ```
     Is inner dockerd runtime = default runc (from containerd.io)?
       YES → PRD-A applicable (pinning containerd.io changes runc version)
       NO (inner runtime = sysbox-runc or other) → PRD-A NOT applicable for this scenario
     ```
   - **Per-image applicability** (verify via Task 1 with evidence-backed statements):
     - `Dockerfile.base`: Expected applicable (cite `src/container/Dockerfile.base:151` - no sysbox-ce, default runc)
     - `Dockerfile.sdks`: Inherits from base - same applicability
     - `Dockerfile.agents`: Inherits from sdks - same applicability (verify no daemon.json override)
     - `Dockerfile.test`: Expected NOT applicable (cite `src/container/Dockerfile.test:60`, `src/configs/daemon-test.json:1` - sysbox-runc)
     - **Note drift**: `src/README.md:279` claims main image includes sysbox with sysbox-runc default - document as drift if code contradicts
   - **Gating note**: If Task 1 reveals different runtime configuration than expected, revise applicability

2. **Technical Background**
   - Reference fn-20-6fe-technical-analysis.md for details
   - How containerd.io version affects runc version (use mapping table from Task 1)
   - Why this is a workaround, not a fix
   - Ownership boundary: host-side vs image-side
   - **Runtime path verification summary** (from Task 1 step 4)

3. **Proposed Changes**
   - Exact containerd.io version to pin (from Task 1 mapping table, or "candidate TBD" if unavailable)
   - **Determine runc packaging** (from Task 1 step 4):
     - If runc bundled in containerd.io: pin containerd.io controls runc
     - If runc is separate package: must pin both containerd.io AND runc
   - **Full pin set** (enumerate all packages from `src/container/Dockerfile.base`):
     - docker-ce
     - docker-ce-cli
     - containerd.io
     - docker-buildx-plugin
     - docker-compose-plugin
     - runc (if separate package - verify from Task 1)
   - **APT dependency consistency proof**:
     - Use `apt-get install --dry-run package=version ...` to verify pin set resolves
     - Document for Ubuntu 24.04 (noble)
   - Dockerfile changes: pin versions explicitly in `apt-get install` command
   - Failure mode if APT repo prunes older versions (document archived pool/snapshot fallback)
   - **Fallback plan** if candidate version is unvalidated: gate implementation behind runtime validation

4. **Security Trade-offs** (Formal Risk Acceptance)
   - **Baseline vs Proposed CVE delta** (from Task 1):
     - runc CVEs between baseline and proposed
     - containerd CVEs between baseline and proposed
     - docker-ce CVEs between baseline and proposed
     - Per-component security delta sources (release notes, GHSA, NVD)
   - Trust boundaries affected:
     - Host (protected by sysbox userns)
     - Sysbox container (agent workspace, secrets, build artifacts)
     - Inner containers
   - **Compensating controls** (validated against actual codebase):
     - Source of truth: `src/lib/container.sh`, `src/lib/doctor.sh`, `src/README.md`
     - Always-on controls (verify against code):
       - Sysbox user namespace isolation
       - Isolation availability check before container start (`src/lib/doctor.sh`)
       - Fail-closed on unknown errors (`src/lib/container.sh`)
     - **Removed/unsupported security bypasses** (from Task 1 step 5 evidence):
       - `--allow-host-credentials` and `--allow-host-docker-socket` are **rejected as "no longer supported"** per `src/lib/container.sh:1164-1186`
       - Classify these as compensating controls: downgrade risk is partially offset by removal of host credential/socket mounting
       - Note: `SECURITY.md:64` is misleading (says "ECI-only features") - document this as docs drift
     - **Docs drift subsection** (from Task 1 step 10):
       - List mismatches between `SECURITY.md`/`src/README.md` and actual code paths
       - Include verified evidence from Task 1 (file paths, line numbers, grep output)
       - Treat code as source of truth, document drift for future doc fixes
   - **Risk acceptance signoff template** (include in PRD):
     ```
     ## Risk Acceptance Signoff

     **Decision**: Accept/Reject temporary CVE rollback
     **Reviewer roles required**: Security Lead, Platform Lead
     **Criteria for acceptance**:
       - [ ] Compensating controls documented and verified against code
       - [ ] Exit criteria defined with specific version gates
       - [ ] Monitoring/alerting for sysbox releases in place
       - [ ] Pin set APT dependency consistency verified
       - [ ] Runtime path verification confirms PRD-A validity
     **Expiry**: This acceptance expires when exit criteria are met or after 90 days (whichever is first)
     **Signatures**:
       - Security Lead: __________ Date: __________
       - Platform Lead: __________ Date: __________
     ```

5. **Implementation Scope** (for future implementation epic)
   - Files to modify: `src/container/Dockerfile.base`
   - Testing requirements
   - Rollout procedure

6. **Exit Criteria**
   - When to remove the workaround (by deployment mode):
     - **Linux Sysbox Mode**: Sysbox release containing fix (commit SHAs from Task 1)
     - **Docker Desktop ECI Mode**: Docker Desktop release incorporating the fix
   - Tracking mechanism (sysbox issue, specific version gates)
   - Upgrade path

## Key context

- PRDs are specification documents, not implementation code
- Security trade-offs require formal risk acceptance framework
- Compatibility matrix must account for Ubuntu codename/arch (Ubuntu 24.04 / noble)
- Use data from Task 1 technical analysis document
- Pin set must be APT dependency-consistent
- **Compensating controls must be validated against code, not just SECURITY.md**
- **ECI support status**: Consume Task 1's "ECI Support Status" section as input - do NOT pre-assume deprecated/supported

## Acceptance

- [ ] PRD-A created at `.flow/specs/prd-runc-downgrade-workaround.md`
- [ ] **Applicability decision tree documented** with per-image conclusions (base/sdks/agents = applicable; test = NOT applicable)
- [ ] Executive summary clearly states temporary nature and scope
- [ ] Technical background references technical analysis document including runtime path verification
- [ ] Proposed changes include:
  - Specific version (from Task 1) or "candidate TBD with validation gate" if unavailable
  - Full pin set enumerated (5-6 packages depending on runc packaging)
  - APT dependency consistency proof mechanism
  - Fallback plan if version is unvalidated
- [ ] Security trade-offs section includes:
  - Baseline-vs-proposed CVE delta for all components, OR "Security review required" section with explicit unknowns + required next probes if data unavailable (mirrors Task 1 gating)
  - Trust boundary analysis
  - Compensating controls validated against code (not just SECURITY.md) with docs drift subsection using verified evidence
  - Risk acceptance signoff template with roles, criteria, and expiry
- [ ] Implementation scope defined for future implementation epic
- [ ] Clear exit criteria with version gates by deployment mode (Sysbox vs ECI as external context)
- [ ] No implementation performed - PRD only

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
