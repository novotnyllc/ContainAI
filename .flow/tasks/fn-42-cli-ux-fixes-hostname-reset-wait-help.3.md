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
Documentation updated to reflect RFC 1123 hostname sanitization and graceful --fresh behavior. Architecture docs explain sanitization rules, troubleshooting has FAQs, and changelog has entries.

## Evidence
- Commits:
- Tests: Verify docs are consistent and readable
- PRs:
<!-- Updated by plan-sync (cross-phase): fn-42-cli-ux-fixes-hostname-reset-wait-help.10 changed hostname approach from short naming to RFC 1123 sanitization -->
