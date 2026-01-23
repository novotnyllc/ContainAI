# fn-10-vep.30 Update SECURITY.md for GitHub advisory pattern

## Description
Update SECURITY.md to use GitHub's recommended security advisory pattern instead of email.

**Size:** S
**Files:**
- `SECURITY.md`

## Approach

1. Remove email-based reporting
2. Add link to GitHub security advisories
3. Document responsible disclosure process
4. Enable GitHub security advisories on repo

## Key content

- How to report vulnerabilities (GitHub Security tab)
- Expected response time
- What information to include
- Scope (what's in/out of scope)
## Acceptance
- [ ] No email-based vulnerability reporting
- [ ] Links to GitHub security advisories
- [ ] Responsible disclosure process documented
- [ ] Expected response time stated
- [ ] Scope clearly defined
- [ ] GitHub security advisories enabled on repo
## Done summary
# fn-10-vep.30 Summary

Updated SECURITY.md to use GitHub's security advisory pattern instead of email-based reporting.

## Changes Made

1. **Removed email-based reporting** - Replaced `security@novotny.org` with GitHub Security Advisories link
2. **Added GitHub Security Advisories link** - Direct link to `https://github.com/novotnyllc/containai/security/advisories/new`
3. **Documented responsible disclosure process** - Added clear 3-step instructions for reporting
4. **Response timeline stated** - 48 hours acknowledgement, 7 days detailed response, severity-based resolution
5. **Scope clearly defined** - Added In Scope and Out of Scope sections

## Acceptance Criteria Met

- [x] No email-based vulnerability reporting
- [x] Links to GitHub security advisories
- [x] Responsible disclosure process documented
- [x] Expected response time stated
- [x] Scope clearly defined
- [ ] GitHub security advisories enabled on repo (requires repo admin action)

Note: Enabling GitHub security advisories requires repository admin access and must be done via GitHub Settings > Security > Advisories.
## Evidence
- Commits:
- Tests: manual review of SECURITY.md changes
- PRs:
