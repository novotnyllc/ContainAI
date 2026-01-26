# fn-20-6fe.1 Investigate runc/sysbox fix mechanism

## Description

Clone sysbox (main repo), sysbox-fs, sysbox-runc, and runc repositories at specific commits. Analyze the fix mechanism and produce technical findings to inform both PRD-A and PRD-B.

**Size:** M (scope includes code archaeology, package mapping, CVE research, and sysctl tracing)
**Files:**
- `.flow/specs/fn-20-6fe-technical-analysis.md` (new file - research artifact)

## Approach

1. Clone repositories and record immutable refs:
   ```bash
   WORKDIR=$(mktemp -d)
   DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

   # Record ContainAI repo commit for file:line evidence anchoring
   CONTAINAI_SHA=$(cd /home/agent/workspace && git rev-parse HEAD)
   echo "containai: $(pwd) @ $CONTAINAI_SHA retrieved $DATE"

   # runc at specific tag
   git clone --depth 1 --branch v1.3.3 https://github.com/opencontainers/runc.git "$WORKDIR/runc"
   RUNC_SHA=$(cd "$WORKDIR/runc" && git rev-parse HEAD)

   # sysbox repos: clone with sparse-checkout, fetch tags for release mapping
   # Note: If fix or version mapping is outside these paths, expand sparse-checkout or do full clone
   git clone --filter=blob:none --sparse https://github.com/nestybox/sysbox.git "$WORKDIR/sysbox"
   cd "$WORKDIR/sysbox" && git sparse-checkout set Makefile go.mod && git fetch --tags
   SYSBOX_SHA=$(git rev-parse HEAD)

   git clone --filter=blob:none --sparse https://github.com/nestybox/sysbox-fs.git "$WORKDIR/sysbox-fs"
   cd "$WORKDIR/sysbox-fs" && git sparse-checkout set seccomp && git fetch --tags
   SYSBOX_FS_SHA=$(git rev-parse HEAD)

   git clone --filter=blob:none --sparse https://github.com/nestybox/sysbox-runc.git "$WORKDIR/sysbox-runc"
   cd "$WORKDIR/sysbox-runc" && git sparse-checkout set libcontainer && git fetch --tags
   SYSBOX_RUNC_SHA=$(git rev-parse HEAD)

   # Record as canonical anchor: URL + SHA + retrieval date
   echo "runc: https://github.com/opencontainers/runc.git @ $RUNC_SHA (v1.3.3) retrieved $DATE"
   echo "sysbox: https://github.com/nestybox/sysbox.git @ $SYSBOX_SHA retrieved $DATE"
   echo "sysbox-fs: https://github.com/nestybox/sysbox-fs.git @ $SYSBOX_FS_SHA retrieved $DATE"
   echo "sysbox-runc: https://github.com/nestybox/sysbox-runc.git @ $SYSBOX_RUNC_SHA retrieved $DATE"
   ```
   - **Immutable ref definition**: URL + `git rev-parse HEAD` + retrieval date = canonical anchor
   - **ContainAI repo anchoring**: Record repo commit SHA for all file:line evidence references
   - **Sparse-checkout fallback**: If `rg openat2` or seccomp-notify plumbing isn't visible in sparse paths, expand checkout (or do full clone) and document which expansions were needed
   - **Rescue snippet** (if tag checkout fails due to shallow/sparse): `git fetch origin tag <tag> --no-tags && git checkout <tag>` or switch to full clone

2. Locate and document the runc security check:
   - Find `RESOLVE_NO_XDEV` usage in filepath-securejoin vendored code
   - Document the exact vendored file/function that emits "unsafe procfs detected" (record resolved path after cloning)
   - Identify what triggers the error
   - Record the resolved runc v1.3.3 commit SHA
   - **Note**: Tag SHA is sufficient for documentation; we will NOT identify the specific introducing commit (would require full history fetch)

3. Locate and document the sysbox fix:
   - Find `openat2` trap configuration in sysbox-runc
   - Analyze seccomp handler in sysbox-fs
   - Record specific commit SHAs that contain the fix
   - Document the seccomp interception mechanism (SECCOMP_IOCTL_NOTIF_ADDFD)
   - **Flag stripping logic (to be verified in code)**: Quote the exact mask/logic from referenced sysbox-fs/sysbox-runc commits; do NOT pre-state the flag set (e.g., `RESOLVE_NO_XDEV | RESOLVE_NO_MAGICLINKS | ...`) as fact without code evidence
   - **Cross-reference procedure for minimum release version**:
     - Hierarchy of authority: release tag → sysbox repo manifest (submodules/Makefile/go.mod) → release artifacts metadata
     - Identify how sysbox-fs/sysbox-runc versions are pinned per release
     - If repos aren't cleanly version-pinned: document as "cannot be derived; requires upstream confirmation" with evidence gathered

4. **Runtime path verification** (critical for PRD-A validity):
   - **Distinguish THREE dockerd/runc loci** (avoid conflation):
     1. **Outer runtime (host)**: sysbox-runc on host that runs the ContainAI sandbox container (host operator controls)
     2. **Inner dockerd (in-image)**: `dockerd` inside the image uses runc from `docker-ce`/`containerd.io` packages in `src/container/Dockerfile.base` - **this is what PRD-A workaround affects**
     3. **ContainAI-managed host dockerd**: `src/lib/docker.sh` defines `/opt/containai/...` bundle + `containai-docker.service` - **this is NOT the same as (2)**
   - **Context selection nuances** (document each):
     - **Inside container**: Uses `default` context (`src/lib/doctor.sh:168-185`) - agent inside sandbox talks to inner dockerd via `/var/run/docker.sock`
     - **On host**: Prefers config override → `containai-docker` → legacy (`src/lib/doctor.sh:160-224`)
     - **Native Linux socket**: `_cai_sysbox_available()` notes native Linux "currently uses default socket" (`src/lib/doctor.sh:340-343`) - verify actual socket/context used
   - **Subsection: Which dockerd does the agent actually use by default?**
     - Check `src/lib/container.sh` for context selection logic (`_containai_resolve_secure_engine_context` → `_cai_select_context`)
     - Check `src/lib/doctor.sh` for `_cai_select_context` call chain (around line 202+)
     - Check `src/lib/docker.sh` for `_cai_expected_docker_host` semantics (nested/container returns `unix:///var/run/docker.sock`)
     - Document service units and env defaults
     - **Native Linux socket verification**: Confirm what socket/context is actually used on native Linux today (evidence from code + config generation)
     - **Scope PRD-A to the inner dockerd (2) failure mode only**
   - **Image artifact inspection** (exhaustive, repo artifacts only):
     - `src/container/Dockerfile.base:151-172`: Docker stack installation - does NOT copy daemon.json
     - `src/container/Dockerfile.base:315-316`: Check ENTRYPOINT/CMD - uses systemd as PID1 (NOT entrypoint.sh)
     - `src/container/Dockerfile.sdks`: Inherits from base - verify no daemon.json override, no entrypoint change
     - `src/container/Dockerfile.agents`: Inherits from sdks - verify no daemon.json override, check for containai-init.service
     - `src/container/Dockerfile.test:84-90`: Copies `src/configs/daemon-test.json` - verify this configures sysbox-runc
     - `src/configs/daemon.json`: **Verify unused by image builds** - grep all Dockerfiles for references; document separately that host setup generates `/etc/containai/docker/daemon.json` independently (`src/lib/setup.sh:2344`)
     - `src/configs/daemon-test.json`: Copied into Dockerfile.test only - check runtime configuration
     - `src/container/entrypoint.sh`: **Gate first**: Is this file used by shipped images? If Dockerfile.base uses systemd, entrypoint.sh analysis may be irrelevant to base image inner dockerd
     - `src/services/docker.service.d/containai.conf`: Systemd drop-in - check if it configures runtime
     - **Confirm sysbox-runc binary existence** in base layer: grep Dockerfiles for sysbox package install
   - **Output format: Inner dockerd runtime configuration evidence table**:
     | File | Line | Evidence | Implication |
     |------|------|----------|-------------|
     | src/container/Dockerfile.base | 151-172 | Docker stack install, no sysbox | Inner uses default runc |
     | src/container/Dockerfile.base | 315-316 | systemd entrypoint | entrypoint.sh not used |
     | src/configs/daemon.json | N/A | grep shows 0 references in Dockerfiles | Unused |
     | src/container/Dockerfile.test | 87 | copies daemon-test.json | Test image uses sysbox-runc |
     - PRD-A references this table verbatim
   - **Determine who provides `/usr/bin/runc` in the image** (artifact-based only):
     - Method: Download .deb packages and inspect contents with `dpkg-deb -c`
     - **Inspect ALL relevant .debs**: `containerd.io`, `docker-ce`, any standalone `runc` package
     - Document whether `runc` comes from `containerd.io` bundle or a separate package
     - Check `docker-ce` dependency constraints via control metadata
     - **Do NOT use runtime container commands** - use .deb inspection only
   - **Conclusion required per image** (evidence-backed statements):
     - ContainAI base image (`Dockerfile.base`): Inner dockerd uses default runc from containerd.io; NO sysbox-ce installed; `src/configs/daemon.json` exists but is NOT copied
     - ContainAI sdks/agents images: Inherit from base, no daemon.json override (verify)
     - ContainAI test image (`Dockerfile.test`): Copies `daemon-test.json` which configures sysbox-runc + installs sysbox-ce 0.6.7
   - **Note**: PRD-A only affects scenario (2) inner dockerd with default runc; if inner runtime is sysbox-runc (test image), pinning `containerd.io` won't help

5. Clarify ownership boundaries by deployment mode + **ECI support status decision**:
   - **ContainAI-managed isolated daemon mode (default)**: `containai-docker` context, sysbox runtime
   - **Docker Desktop ECI Mode - SUPPORT STATUS DECISION REQUIRED**:
     - **Decision question**: Is Docker Desktop a **documented and exercised** engine for `cai`? (not just "could work if user sets override")
     - **Evidence to gather from codebase** (exhaustive list):
       - Check `src/containai.sh` for sandbox command status
       - Check if `src/lib/eci.sh` exists
       - Check `src/lib/doctor.sh` for `_cai_select_context` - does it ever select default context on host?
       - Check `src/lib/docker.sh` for Docker Desktop detection (`_cai_docker_desktop_version`) - is it called anywhere?
       - Check `src/lib/container.sh:1237-1255` for config override mechanism
       - Check `SECURITY.md` for ECI references and cross-reference with actual code
       - Check `src/README.md` for ECI/sandbox documentation vs code reality
       - Check `src/lib/container.sh` for `--allow-host-credentials` and `--allow-host-docker-socket` handling
       - Check if `cai setup` defaults ever target Docker Desktop
     - **Expected findings** (verify and document with file paths + line numbers):
       - `src/containai.sh:356-371`: "sandbox command removed, now uses Sysbox"
       - `src/lib/eci.sh`: File does not exist
       - `src/lib/doctor.sh:168-185`: Inside container uses `default` context (inner dockerd)
       - `src/lib/doctor.sh:160-224`: On host, prefers config override → `containai-docker` → legacy
       - `src/lib/docker.sh:229-303`: `_cai_docker_desktop_version` defined but **verify if called** - if unused, this is strong evidence ECI is unimplemented
       - `SECURITY.md:25,134`: References `src/lib/eci.sh` which doesn't exist
       - `src/README.md:44-52,145-146`: Documents Docker sandbox/ECI but CLI removed sandbox command
       - `src/lib/container.sh:1164-1186`: `--allow-host-credentials` and `--allow-host-docker-socket` are rejected as "no longer supported"
     - **Output**: Produce "ECI Support Status (as-of repo commit)" section with:
       - Commit SHA or date of analysis
       - Code evidence (file:line references)
       - Verdict: "unsupported" or "supported" based on evidence
     - **Hard decision rule**: "ECI supported" ONLY IF:
       1. `cai setup` or defaults actively target Docker Desktop, OR
       2. Code paths actively use Docker Desktop/ECI features (not just "could work if user sets config override")
       - If `_cai_docker_desktop_version` is defined but never called: strong evidence ECI is unimplemented
       - Config override allowing arbitrary context ≠ ECI being "supported" (user can override many things)
     - **Decision for PRDs**: If ECI is unsupported, PRD-A/PRD-B treat it as "external ecosystem context only" (not a supported deployment target)
   - **Image-side (ContainAI-controlled)**: containerd.io/runc packages in Dockerfile

6. Investigate the sysctl OCI spec source (local-first, then version-anchored upstream):
   - **Proof standard**: To claim a source, must cite exact file/function at an anchored upstream tag; anything else is hypothesis
   - **Known challenge**: This repo contains no reference to `net.ipv4.ip_unprivileged_port_start`; pure static tracing may be inconclusive
   - **Step 1: Search this repo first** for sysctl injection points:
     - `src/lib/setup.sh` (host daemon config generation - NOT inner Docker config)
     - `src/configs/daemon.json`, `src/configs/daemon-test.json`
     - Check if Dockerfiles copy any daemon.json with sysctl config
     - Check for `--sysctl` flags in container run commands (`src/lib/container.sh`)
   - **Step 2: Record and anchor image package versions** (by Git commit where possible):
     - Method: `apt-cache policy docker-ce containerd.io` in ubuntu:24.04 with Docker apt repo configured
     - For version → commit anchoring: check package metadata/changelogs for Git commit IDs
     - Map Docker Engine version to Moby release tag (note: packaging revisions may differ - mark as "best-effort")
     - **Fallback**: If 1:1 mapping not possible, search sysctl name across candidate tags
   - **Step 3: Upstream source trace at anchored versions**:
     - moby/moby at specific tag: `daemon/oci_linux.go`, `oci/defaults.go`, `daemon/config/config.go`
     - containerd at specific tag: `pkg/oci/spec.go`, `oci/spec_opts.go`
     - sysbox: `libsysbox/syscont/spec.go`, sysbox documentation
   - **Hard stop (early exit)**: If not provable from pinned upstream tags within investigation scope:
     - Document as "hypothesis: likely injected by [component] based on [partial evidence]"
     - Specify the smallest future runtime probe needed: e.g., "run container, inspect OCI spec via `ctr` or `runc spec`"
     - PRDs must treat this as unverified and not make claims requiring this knowledge

7. Document Docker stack → runc version mapping (artifact-based):
   - **Scope**: This analysis is for **Ubuntu 24.04 (noble) only**; other codenames require separate verification
   - **Prerequisite**: Configure Docker apt repo for Ubuntu 24.04 (noble) **exactly matching `Dockerfile.base:151-166`**:
     ```bash
     # Add Docker GPG key and repo (exact Dockerfile.base pattern)
     install -m 0755 -d /etc/apt/keyrings
     curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
     chmod a+r /etc/apt/keyrings/docker.asc
     echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list
     apt-get update
     ```
   - **Clarification on artifact inspection**: No ContainAI/DinD reproduction; offline artifact inspection allowed (including throwaway Ubuntu env for apt/dpkg operations)
   - **Inspect ALL installed .debs relevant to runc provenance** (not just containerd.io):
     - `containerd.io`: Primary candidate for bundled runc
     - `docker-ce`: Check dependency constraints and whether it ships runc
     - Any standalone `runc` package if present
   - **Determine from step 4**: Is `runc` bundled in `containerd.io` or a separate package?
   - **If bundled in containerd.io**:
     - Download .deb packages and inspect embedded runc binary version
     - Version selection: first bundling runc >= 1.3.3 (broken), immediately previous (candidate-good), one older fallback
     - **Also verify docker-ce dependency constraints** via control metadata to ensure pin is consistent
   - **If separate runc package**:
     - Document that both `containerd.io` AND `runc` must be pinned
     - Map both packages to safe versions
   - Steps:
     - List available versions: `apt-cache policy containerd.io docker-ce`
     - Download .debs: `apt download containerd.io=<version> docker-ce=<version>`
     - Extract: `dpkg-deb -x <pkg>.deb ./extracted`
     - Check runc version (prefer non-exec inspection to avoid cross-arch issues):
       1. **Primary**: `dpkg-deb -f <pkg>.deb | grep Version` or package changelog
       2. **Secondary**: `strings ./extracted/usr/bin/runc | grep -E '^[0-9]+\.[0-9]+\.[0-9]+'` or `go tool buildinfo` if available
       3. **Optional/best-effort**: `./extracted/usr/bin/runc --version` (may fail cross-arch)
     - **Check control metadata**: `dpkg-deb -I <pkg>.deb` to verify dependency constraints
   - Record: package URL, SHA256 of .deb, extracted runc version string, dependency constraints
   - **Multi-architecture requirement**: Map versions for both `amd64` AND `arm64` since container images are built multi-arch; or explicitly document single-arch limitation if not feasible
   - **APT pruning contingency workflow** (if older versions unavailable via apt indices):
     1. Stop at "candidate pins unknown via apt"
     2. **Direct pool URL discovery** (concrete method):
        - Download apt `Packages` index: `curl https://download.docker.com/linux/ubuntu/dists/noble/stable/binary-amd64/Packages`
        - Grep for target package version to get `Filename:` field (e.g., `pool/stable/amd64/containerd.io_<version>_amd64.deb`)
        - Construct full URL: `https://download.docker.com/linux/ubuntu/<Filename>`
        - Repeat for arm64: `dists/noble/stable/binary-arm64/Packages`
     3. If pool URLs found: download directly, verify SHA256, proceed with analysis
     4. If pool URLs NOT found: document "cannot locate via apt indices or pool; requires vendor assistance or alternative source"
     5. **Immutable anchor requirement**: For any pinned artifact, capture SHA256 + full download URL as the real anchor
     6. PRD-A must specify: "pin by SHA256-verified .deb from direct pool URL" or require security/platform review before choosing any downgrade

8. Extract CVE/security advisory data (narrowed scope):
   - **Step 1: Record current baseline** (date + package versions from `apt-cache policy` with Docker repo configured)
   - **Step 2: Define proposed pin versions** (from step 7)
   - **Step 3: CVE set filtered by impact class**:
     - **Primary filter**: Impact class (container-escape, privilege-escalation, arbitrary code execution) - include ALL advisories in these classes regardless of CVSS
     - **Secondary filter**: High/Critical severity for other impact classes
     - **Primary focus**: CVEs explicitly fixed by runc ≥1.3.3 (the driver for the downgrade decision)
     - **Secondary**: Any *forced* engine/containerd downgrades required for dependency consistency
   - **Note what's excluded**: Document any Medium-severity CVEs excluded and why (not in escape/priv-esc class)
   - Record: CVE ID, severity (CVSS), impact class, affected versions, fix version, component, source (link)
   - **Output format**: "Baseline as of YYYY-MM-DD + exact resolved package versions" vs proposed delta
   - **Gate**: If data can't be obtained reliably, gate implementation on security review

9. Build environment/reproduction matrix (observed/reported outcomes):
   - **Scope**: Based on upstream issue reports and observed behavior, NOT runtime testing
   - **Mandatory rows** (keyed by ContainAI repo artifacts):
     - ContainAI base image (`src/container/Dockerfile.base`): inner runtime = default runc
     - ContainAI test image (`src/container/Dockerfile.test` + sysbox-ce 0.6.7): inner runtime = sysbox-runc
   - **Additional columns**: Deployment mode (Sysbox/ECI), Host sysbox version, Inner dockerd version, Inner runc version
   - **Outcome column**: "reported fail", "reported success", "unknown"
   - **Confidence + source**: issue link, build date, or "inferred from code"
   - **Conflict resolution**: If sources conflict, document both with confidence levels
   - Reference upstream issues: sysbox#973, sysbox#972, runc#4968

10. Document docs drift (first-class section in technical analysis):
    - **Impact on decision-making**: What the code actually does today vs what docs claim
    - **Drift items to verify** (gather evidence for each):
      - **Verify**: Does `SECURITY.md` reference `src/lib/eci.sh`? Does that file exist? Record actual line numbers and grep output.
      - **Verify**: Does `src/README.md` claim sysbox or sysbox-runc is default? What does `Dockerfile.base` actually install? Record grep output.
      - **Verify**: What does `src/containai.sh` sandbox command handler say? What do `SECURITY.md` and `src/README.md` say about ECI/sandbox?
      - **Verify**: Does `src/lib/doctor.sh` contain ECI-specific detection code? (grep for "eci", "ECI", "enhanced container")
    - **Output format**: For each drift item, record:
      - File + line number
      - Actual content (quoted)
      - Expected vs actual behavior
    - PRDs must cite code paths as source of truth, not docs
    - This drift materially affects "deployment mode" taxonomy and ownership boundaries in both PRDs

11. Produce technical analysis document at `.flow/specs/fn-20-6fe-technical-analysis.md`

## Key context

- This is research only - no ContainAI code/runtime changes; networked research (cloning, apt downloads, CVE lookups) is allowed; no integration tests
- Pin analysis to immutable refs with recorded SHAs (after sparse-checkout fetch)
- Technical analysis will be referenced by both PRD-A and PRD-B
- Treat version predictions as hypotheses, not facts
- **PRD-A validity depends on step 4**: If inner runtime is sysbox-runc (not image runc), PRD-A workaround may be ineffective for that scenario
- **Decision rule**: If mapping can't conclusively identify a safe version, document a *candidate* pin with explicit "requires validation" gate

## Acceptance

- [ ] **ContainAI repo anchored**: Repo commit SHA recorded in technical analysis header for file:line evidence consistency
- [ ] **Upstream repos cloned**: Immutable refs recorded (URL + `git rev-parse HEAD` + retrieval date); sparse-checkout expansions documented if needed
- [ ] runc security check documented (resolved vendored file path, function, flags, error condition; tag SHA sufficient, no introducing commit needed)
- [ ] sysbox fix mechanism documented (seccomp trap, fd injection); flag stripping logic quoted from code (not pre-stated)
- [ ] Sysbox fix cross-referenced with release manifest using defined hierarchy (or documented as "cannot be derived; requires upstream confirmation" with evidence gathered)
- [ ] **Runtime path verified**:
  - THREE dockerd/runc loci distinguished (outer host, inner in-image, containai-managed)
  - Per-image conclusions (base, sdks, agents, test) with evidence-backed statements citing file:line
  - Explicit documentation that `src/configs/daemon.json` is NOT copied into Dockerfile.base
  - `/usr/bin/runc` provider documented via .deb inspection (containerd.io + docker-ce + any standalone runc)
- [ ] **ECI Support Status section produced** with commit SHA, code evidence (file:line refs), hard decision rule applied (detection + UX integration), and verdict (deprecated/unsupported or supported)
- [ ] Ownership boundary clarified by deployment mode, PRD-A/PRD-B to consume ECI decision as input
- [ ] Sysctl OCI spec source traced with proof standard (exact file/function at anchored tag), or hard-stop with hypothesis + smallest runtime probe specified
- [ ] Docker stack → runc version mapping (Ubuntu 24.04/noble): Both amd64 AND arm64 mapped with SHA256 + pool URLs; or single-arch with explicit limitation documented
- [ ] CVE/security advisory data extracted filtered by impact class (escape/priv-esc = all; others = High/Critical), or gated on security review if data unavailable
- [ ] Environment/reproduction matrix with mandatory ContainAI image rows
- [ ] Docs drift documented as first-class section with verified evidence (file paths, line numbers, grep output) including `src/README.md:279` claim
- [ ] Technical analysis document created at `.flow/specs/fn-20-6fe-technical-analysis.md`

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
