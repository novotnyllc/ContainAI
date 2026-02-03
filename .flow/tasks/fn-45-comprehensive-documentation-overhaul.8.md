# fn-45-comprehensive-documentation-overhaul.8 Create documentation link validation script

## Description
Create a shell script that validates all internal documentation links (relative links between markdown files and anchors). This ensures "All internal doc links validated" acceptance criterion can be reliably verified.

**Size:** M (upgraded from S due to comprehensive link handling)
**Files:** `scripts/check-doc-links.sh` (new)

## Approach

1. Create `scripts/check-doc-links.sh` that:
   - Finds all markdown files in `docs/` and root (`README.md`, `SECURITY.md`, etc.)
   - Extracts ALL internal links (not just prefixed paths)
   - Validates that target files exist
   - Validates that anchor targets (`#section-name`) exist in target files
   - Reports broken links with file:line context
   - Returns non-zero exit code if any broken links found

2. **Link patterns to handle** (comprehensive):
   - Relative paths with prefix: `[text](docs/foo.md)`, `[text](./foo.md)`, `[text](../README.md)`
   - **Bare relative paths**: `[text](SECURITY.md)`, `[text](LICENSE)`, `[text](src/README.md)`
   - **Same-file anchors**: `[text](#section-name)` (TOC/in-page links)
   - Paths with anchors: `[text](docs/foo.md#section)`, `[text](SECURITY.md#threat-model)`

3. **Link detection rule**:
   - Match any `[text](target)` where target does NOT start with:
     - `http://`, `https://`, `mailto:`, `ftp://` (external URLs)
     - `data:` (data URIs)
   - This captures all relative paths regardless of prefix

4. **Anchor validation with duplicate heading handling**:
   - Extract heading anchors from target file
   - GitHub anchor format: lowercase, spaces→hyphens, remove special chars
   - Example: `## Quick Reference` → `#quick-reference`
   - **Handle duplicate headings like GitHub**:
     - First occurrence: `#heading-name`
     - Second occurrence: `#heading-name-1`
     - Third occurrence: `#heading-name-2`
   - Track duplicate counts per heading slug per file

5. **Same-file anchor validation**:
   - For `(#anchor)` links, validate against the current file's anchor set
   - Common in README.md TOC sections
   - Must work with duplicate heading handling

6. Output format:
   ```
   Checking docs/foo.md...
     [ERROR] Line 42: SECURITY.md does not exist
     [ERROR] Line 56: #nonexistent-anchor - anchor not found in this file
     [ERROR] Line 78: docs/bar.md#section - anchor not found in target
   ...
   Summary: 3 broken links in 1 file
   ```

7. Integration:
   - Can be run manually: `./scripts/check-doc-links.sh`
   - Can be added to CI (GitHub Actions) later
   - Exit 0 = all links valid, Exit 1 = broken links found

## Key context

Current link validation suggestion in epic is just `grep -r '\[.*\](docs/' README.md docs/` which doesn't actually verify targets exist.

**Known link patterns in repo**:
- `[LICENSE](LICENSE)` - bare file reference
- `[SECURITY](SECURITY.md)` - bare md reference
- `[section](#overview)` - same-file anchor
- `[docs](docs/quickstart.md#setup)` - path with anchor

**Known files with duplicate headings** (must handle correctly):
- `docs/security-scenarios.md`
- `docs/setup-guide.md`

## Acceptance
- [ ] Script validates ALL relative markdown links (not just prefixed paths)
- [ ] **Script validates bare paths** like `(SECURITY.md)`, `(LICENSE)`, `(src/README.md)`
- [ ] **Script validates same-file anchors** like `(#section-name)`
- [ ] Script validates anchors in cross-file links
- [ ] **Script handles duplicate headings correctly** (adds -1, -2 suffix like GitHub)
- [ ] Script excludes external URLs (http, https, mailto, etc.)
- [ ] Script reports file:line for each broken link
- [ ] Script returns non-zero exit code on broken links
- [ ] Script is executable and works with bash
- [ ] Script documented in CONTRIBUTING.md or README (brief mention)
- [ ] Example output shown in script header comments

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
