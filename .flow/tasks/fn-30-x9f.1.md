# fn-30-x9f.1 Fix sysbox version parsing for multiline output format

## Description
Fix sysbox version detection functions to handle both old single-line and new multiline output formats from `sysbox-runc --version`. Currently returns empty string (but exit 0) when parsing fails, causing false "upgrade available" messages.

**Size:** M
**Files:** `src/lib/setup.sh`

## Approach

1. Extend `_cai_sysbox_installed_binary_version()` to handle BOTH output formats:
   - New multiline: Parse `version:` line
   - Old single-line: Parse `sysbox-runc version X.Y.Z...` format
   - Return non-zero if neither format matches

2. Update `_cai_sysbox_installed_version()` to:
   - Call `_cai_sysbox_installed_binary_version()` and extract semver from result
   - Return non-zero if no semver could be extracted (fail explicitly, don't return empty string with exit 0)

3. Sweep for all raw `sysbox-runc --version` calls:
   ```bash
   rg "sysbox-runc --version" src/lib/*.sh
   ```
   Replace with appropriate version function calls

4. Fix display in `_cai_install_sysbox()` to use version function instead of raw command

## Key context

Two output formats from `sysbox-runc --version`:
- Old: `sysbox-runc version 0.6.7+containai.20260127` (single line)
- New: Multiline with `version:` on line 3

The critical bug is that `sed -n` with no match returns empty string AND exit 0, so caller thinks version="" is valid.
## Approach

1. Update `_cai_sysbox_installed_version()` (line 483-491) to parse version from multiline output
   - Option A: Reuse logic from `_cai_sysbox_installed_binary_version()` (lines 497-513) which already handles this correctly
   - Option B: Use `grep` for "version:" line then extract semver
   - Prefer Option A for consistency - extract semver from binary version

2. Fix `$existing_version` display at line 914 to use proper version function instead of raw `sysbox-runc --version | head -1`

## Key context

The multiline format from sysbox-runc looks like:
```
sysbox-runc
        edition:        Community Edition (CE)
        version:        0.6.7+containai.20260127
```

`_cai_sysbox_installed_binary_version()` at lines 497-513 already handles this correctly by grepping for `version:` line.
## Acceptance
- [ ] `_cai_sysbox_installed_binary_version()` returns full version from BOTH formats (old single-line and new multiline)
- [ ] `_cai_sysbox_installed_binary_version()` returns non-zero when it cannot parse version
- [ ] `_cai_sysbox_installed_version()` returns semver (e.g., "0.6.7") from both formats
- [ ] `_cai_sysbox_installed_version()` returns non-zero when no semver can be extracted
- [ ] Setup/update display shows actual version string, not "sysbox-runc"
- [ ] `cai update` with identical versions reports "Sysbox is current"
- [ ] No raw `sysbox-runc --version | head -1` calls remain in version display paths
## Done summary
Fixed sysbox version parsing to handle both old single-line and new multiline output formats
## Evidence
- Commits: 605d028
- Tests:
- PRs:
