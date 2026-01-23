# fn-10-vep.56 Add --dry-run flag to cai run/shell commands

## Description
Add `--dry-run` flag to `cai run` and `cai shell` commands.

**Size:** S
**Files:** lib/container.sh

## Approach

1. Add `--dry-run` flag parsing to run/shell commands
2. When set, print what would happen instead of executing:
   - Container name to be created/used
   - Port to be allocated
   - Volumes to be mounted
   - SSH connection details
3. Use consistent output format (good for scripting)

## Key context

- Dry-run is valuable for understanding what cai will do
- Output should be machine-parseable (one item per line, key=value)
## Acceptance
- [x] `--dry-run` flag added to `cai run` and `cai shell`
- [x] Shows container name that would be used
- [x] Shows port that would be allocated
- [x] Shows volumes that would be mounted
- [x] Shows SSH connection command that would be run
- [x] No actual container created or modified
- [x] Output is machine-parseable
## Done summary
Added --dry-run flag to cai run and cai shell commands with machine-parseable output (key=value format, one per line)
## Evidence
- Commits: pending
- Tests: bash syntax validation passed
- PRs:
