# fn-45-comprehensive-documentation-overhaul.6 Document recent CLI and security changes

## Description
Update documentation to reflect recent CLI and security changes from fn-41 (silent by default) and fn-43 (network security). Also fix incorrect isolation mode claims in SECURITY.md that reference non-existent ECI mode.

**Size:** M (upgraded from S due to SECURITY.md corrections)
**Files:**
- `docs/quickstart.md`
- `docs/cli-reference.md` (created in .2)
- `SECURITY.md`
- `README.md` (if needed)

## Approach

1. **Silent CLI (fn-41)** updates:
   - Add verbosity section to quickstart explaining default behavior
   - Document `--verbose` flag and `CONTAINAI_VERBOSE` in CLI reference
   - Update any examples that rely on verbose output

2. **Network Security (fn-43)** updates:
   - Add section to SECURITY.md documenting:
     - Private IP blocking (RFC 1918, link-local)
     - Metadata endpoint blocking (169.254.169.254)
     - How to verify it's working
   - Update security-scenarios.md if relevant

3. **CRITICAL: Fix SECURITY.md isolation mode claims**:
   - Current SECURITY.md claims "ECI Mode (Docker Desktop 4.50+) via `docker sandbox`"
   - References non-existent `src/lib/eci.sh`
   - **Actual implementation**: Sysbox runtime via dedicated `containai-docker` engine
   - Actions:
     - Remove/correct ECI mode claims
     - Document actual isolation: Sysbox + containai-docker context
     - Keep Docker Desktop sandbox/ECI as *comparative alternatives* (link to `docs/security-comparison.md`)
     - Update any diagrams showing incorrect architecture

4. Verify changes against:
   - CHANGELOG.md entries for fn-41 and fn-43
   - Actual implementation in `src/lib/container.sh` (line 1014: sysbox-runc check)
   - `src/lib/docker.sh` (containai-docker constants)

## Key context

fn-41: CLI is now silent by default. `--verbose` or `CONTAINAI_VERBOSE=1` enables info output. `--quiet` suppresses warnings. Precedence: --quiet > --verbose > env var.

fn-43: Container network security hardens against SSRF and cloud metadata attacks. Private IPs and metadata endpoints blocked by default.

**SECURITY.md mismatch details**:
- Incorrect: Claims ECI mode via `docker sandbox`, references `src/lib/eci.sh`
- Correct: Uses Sysbox runtime (`sysbox-runc`) via dedicated Docker engine (`containai-docker`)
- Evidence: `src/lib/container.sh:1014` checks for `sysbox-runc`, `src/lib/docker.sh:311-321` defines containai-docker paths

## Acceptance
- [ ] Quickstart mentions silent default and --verbose flag
- [ ] CLI reference documents verbosity flags and env vars
- [ ] SECURITY.md documents network blocking policy (fn-43)
- [ ] **SECURITY.md isolation claims corrected to match Sysbox/containai-docker implementation**
- [ ] **References to non-existent ECI mode/eci.sh removed**
- [ ] **Docker Desktop sandbox/ECI mentioned only as comparative alternatives** (link to security-comparison.md)
- [ ] Any examples expecting verbose output updated
- [ ] Changes verified against actual CLI behavior
- [ ] No outdated screenshots or output examples

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
