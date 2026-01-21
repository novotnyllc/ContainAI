# fn-10-vep.58 Support --name flag for custom container names

## Description
Support `--name` flag for custom container names.

**Size:** S
**Files:** lib/container.sh

## Approach

1. Add `--name` flag to run/shell commands
2. If provided, use exact name instead of hash-based naming
3. Container with that name must match workspace (validate label)
4. Useful for memorable names: `--name myproject-dev`

## Key context

- Overrides the default `containai-{hash}` naming
- Still validates workspace match via label
## Acceptance
- [ ] `--name` flag added to `cai run` and `cai shell`
- [ ] Custom name used if provided
- [ ] Workspace validation via label still works
- [ ] Clear error if container exists for different workspace
- [ ] Help text documents the flag
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
