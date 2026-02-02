# fn-45-comprehensive-documentation-overhaul.6 Document recent CLI and security changes

## Description
Update documentation to reflect recent CLI and security changes from fn-41 (silent by default) and fn-43 (network security). These changes landed but docs haven't fully caught up.

**Size:** S
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

3. Verify changes against:
   - CHANGELOG.md entries for fn-41 and fn-43
   - Actual implementation in src/

## Key context

fn-41: CLI is now silent by default. `--verbose` or `CONTAINAI_VERBOSE=1` enables info output. `--quiet` suppresses warnings. Precedence: --quiet > --verbose > env var.

fn-43: Container network security hardens against SSRF and cloud metadata attacks. Private IPs and metadata endpoints blocked by default.
## Acceptance
- [ ] Quickstart mentions silent default and --verbose flag
- [ ] CLI reference documents verbosity flags and env vars
- [ ] SECURITY.md documents network blocking policy
- [ ] Any examples expecting verbose output updated
- [ ] Changes verified against actual CLI behavior
- [ ] No outdated screenshots or output examples
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
