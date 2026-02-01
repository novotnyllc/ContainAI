# fn-42-cli-ux-fixes-hostname-reset-wait-help.12 Update documentation for new hostname feature

## Description
Update documentation to explain the new RFC 1123 hostname feature. When containers are created, their names are automatically sanitized to be valid UNIX hostnames.

**Size:** S
**Files:** `docs/architecture.md`, `docs/troubleshooting.md`, `CHANGELOG.md`

## Approach

1. **docs/architecture.md** - Container Lifecycle section:
   - Explain that every container gets a hostname matching a sanitized version of its name
   - Document the sanitization rules from `_cai_sanitize_hostname()`:
     - Lowercase conversion
     - Underscore to hyphen replacement
     - Invalid character removal
     - Multiple hyphen collapsing
     - 63-character max (RFC 1123 limit)
   - Note the fallback to "container" if sanitization results in empty string

2. **docs/troubleshooting.md**:
   - Add FAQ: "Why does my hostname differ from my container name?"
   - Example: container name `my_workspace` becomes hostname `my-workspace`
   - Note that this ensures compatibility with UNIX hostname standards

3. **CHANGELOG.md**:
   - Add "Added" entry: "RFC 1123 compliant hostnames for all containers"

## Key context

- RFC 1123 allows: lowercase letters, numbers, hyphens
- No leading/trailing hyphens, max 63 chars per label
- Hostname sanitization at `src/lib/container.sh:313-336`

## Acceptance
- [ ] docs/architecture.md explains RFC 1123 hostname sanitization
- [ ] Container lifecycle documentation includes hostname info
- [ ] Troubleshooting FAQ explains name vs hostname differences
- [ ] CHANGELOG.md entry added
- [ ] No conflicting documentation with other tasks

## Done summary
## Summary
Updated documentation to explain RFC 1123 hostname feature:

1. **docs/architecture.md** - Added "Container Naming and Hostname" section under Container Lifecycle:
   - Explains that containers get RFC 1123 compliant hostnames
   - Documents all sanitization rules from `_cai_sanitize_hostname()`
   - Includes example transformations table

2. **docs/troubleshooting.md** - Added "Hostname Issues" FAQ:
   - Added to Quick Reference table
   - Added to Quick Links
   - New section explaining why hostname differs from container name
   - Added to Error Message Reference

3. **CHANGELOG.md** - Added entry under [Unreleased] → Added:
   - "RFC 1123 compliant hostnames for all containers"
## Evidence
- Commits:
- Tests: Documentation verification via grep confirmed RFC 1123 references in all target files
- PRs:
