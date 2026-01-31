# fn-42-cli-ux-fixes-hostname-reset-wait-help.3 Update docs: hostname and --fresh behavior

## Description
Update documentation to reflect new short container naming and --fresh wait behavior.

**Size:** S
**Files:** `docs/architecture.md`, `docs/troubleshooting.md`, `CHANGELOG.md`, `README.md`

## Approach

1. **README.md** - Update container lifecycle section:
   - Document new naming format: `cai-XXXX-YYYY` (max 16 chars)
   - Note that shell prompt shows short container name

2. **docs/architecture.md** - Container Lifecycle section:
   - Explain naming scheme: 4-char repo hint + 4-char hash
   - Migration: existing containers keep names until --fresh

3. **docs/troubleshooting.md**:
   - Update --fresh examples
   - Add FAQ: "How do I get the new short container names?"
   - Add FAQ: "Why does my SSH session wait during --fresh?"

4. **CHANGELOG.md**:
   - Add "Changed" entry for new naming scheme
   - Add "Changed" entry for graceful --fresh behavior

## Key context

- Keep-a-changelog format for CHANGELOG.md
- Troubleshooting uses symptom → diagnosis → steps format
## Approach

1. **docs/architecture.md** - Container Lifecycle section:
   - Document that container hostname matches container name
   - Note truncation to 63 chars for long names

2. **docs/troubleshooting.md**:
   - Update --fresh examples to note graceful reconnection
   - Add FAQ: "Why does my SSH session wait during --fresh?"

3. **CHANGELOG.md**:
   - Add "Added" entry for hostname matching
   - Add "Changed" entry for graceful --fresh behavior

## Key context

- Keep-a-changelog format for CHANGELOG.md
- Troubleshooting uses symptom → diagnosis → steps format
## Acceptance
- [ ] README.md updated with new naming format
- [ ] docs/architecture.md explains naming scheme
- [ ] docs/troubleshooting.md has --fresh FAQs
- [ ] CHANGELOG.md entries added
- [ ] No conflicting info with existing docs
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
