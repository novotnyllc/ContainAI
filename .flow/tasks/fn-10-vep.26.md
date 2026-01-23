# fn-10-vep.26 Add version management and update mechanism

## Description
Add version management with single source of truth and update mechanism.

**Size:** M
**Files:**
- `VERSION` (source of truth)
- `src/containai.sh` (add version/update commands)
- `src/lib/version.sh` (new)

## Approach

1. VERSION file at repo root (e.g., "0.1.0")
2. `cai version` command shows current version
3. `cai update` command:
   - Pulls latest from git/GHCR
   - Shows changelog if available
   - Rebuilds image if needed

## Key context

- Single source of truth: VERSION file
- Build script should embed version in image
- Update should handle both git-based and GHCR-based installs
## Acceptance
- [x] VERSION file at repo root
- [x] `cai version` shows current version
- [x] `cai update` pulls latest changes
- [x] Version embedded in Docker image labels
- [x] Update works for git-cloned installs
- [x] Update works for GHCR-based installs (shows docker pull guidance)
## Done summary
## Summary

Added version management with single source of truth (VERSION file) and update mechanism:

1. **Created `src/lib/version.sh`** - New library with:
   - `_cai_get_version()` - Reads version from VERSION file
   - `_cai_version()` - Shows version with `--json` option for machine parsing
   - `_cai_update()` - Updates git-based installations with `--check` option

2. **Integrated into `src/containai.sh`**:
   - Added version.sh to library loading
   - Added `version` and `update` subcommands
   - Updated help text

3. **Key features**:
   - VERSION file at repo root is single source of truth (already existed)
   - `cai version` shows current version and install type
   - `cai update` fetches/pulls latest from git, shows changelog diff
   - `cai update --check` checks for updates without installing
   - Handles local changes with confirmation prompt
   - Docker image labels already embed version via build args
## Evidence
- Commits:
- Tests: {'name': 'cai version', 'command': 'source src/containai.sh && cai version', 'result': 'pass', 'output': 'ContainAI version 0.1.0'}, {'name': 'cai version --json', 'command': 'source src/containai.sh && cai version --json', 'result': 'pass', 'output': '{"version":"0.1.0","install_type":"git","install_dir":"..."}'}, {'name': 'cai version --help', 'command': 'source src/containai.sh && cai version --help', 'result': 'pass'}, {'name': 'cai update --help', 'command': 'source src/containai.sh && cai update --help', 'result': 'pass'}, {'name': 'syntax check version.sh', 'command': 'bash -n src/lib/version.sh', 'result': 'pass'}
- PRs:
