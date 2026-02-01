# fn-42-cli-ux-fixes-hostname-reset-wait-help.3 Update docs: hostname and --fresh behavior

## Description
Update documentation to reflect new short container naming and --fresh wait behavior.

**Size:** S
**Files:** `docs/architecture.md`, `docs/troubleshooting.md`, `CHANGELOG.md`, `README.md`

## Approach

1. **README.md** - Update container lifecycle section:
   - Document that containers now have RFC 1123 compliant hostnames
   - Note hostname is sanitized version of container name
   - Explain sanitization rules: lowercase, underscores→hyphens, max 63 chars

2. **docs/architecture.md** - Container Lifecycle section:
   - Explain RFC 1123 hostname sanitization
   - Document `_cai_sanitize_hostname()` function
   - Note how container name with underscores becomes valid hostname

3. **docs/troubleshooting.md**:
   - Update --fresh examples to show hostname in container
   - Add FAQ: "Why does my hostname differ from container name?"
   - Add FAQ: "Why does my SSH session wait during --fresh?"

4. **CHANGELOG.md**:
   - Add "Added" entry for RFC 1123 hostname support
   - Add "Changed" entry for graceful --fresh behavior

## Key context

- Keep-a-changelog format for CHANGELOG.md
- Troubleshooting uses symptom → diagnosis → steps format
- RFC 1123 compliance ensures hostname works across UNIX/Linux systems
## Acceptance
- [ ] README.md updated with RFC 1123 hostname info
- [ ] docs/architecture.md explains hostname sanitization
- [ ] docs/troubleshooting.md has hostname and --fresh FAQs
- [ ] CHANGELOG.md entries added for hostname feature and graceful --fresh
- [ ] No conflicting info with existing docs
- [ ] Hostname behavior documented (container name vs hostname differences)
## Done summary
## Summary

Updated documentation to reflect RFC 1123 hostname sanitization and graceful --fresh/--reset behavior:

### Changes Made:

1. **README.md**: Added "RFC 1123 Hostnames" section under Key Capabilities explaining that containers receive RFC 1123 compliant hostnames (e.g., underscores become hyphens)

2. **CHANGELOG.md**: Added entry for graceful `--fresh` and `--reset` behavior with SSH wait (up to 60 seconds with exponential backoff)

3. **docs/troubleshooting.md**:
   - Added new FAQ: "Why does my SSH session wait during --fresh?" explaining the container recreation and SSH wait process
   - Added entry to Quick Reference table for SSH wait during --fresh
   - Added entry to Error Message Reference appendix

### Files Modified:
- `README.md`
- `CHANGELOG.md`
- `docs/troubleshooting.md`

### Verification:
- docs/architecture.md already had Container Naming and Hostname section with sanitization rules (lines 240-272)
- docs/troubleshooting.md already had Hostname Issues FAQ (lines 1287-1343)
- CHANGELOG.md already had RFC 1123 hostname entry (line 11)
- All documentation is consistent and cross-referenced
## Evidence
- Commits:
- Tests:
- PRs:
