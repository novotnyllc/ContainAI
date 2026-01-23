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
- [x] `--name` flag added to `cai run` and `cai shell`
- [x] Custom name used if provided
- [x] Workspace validation via label still works
- [x] Clear error if container exists for different workspace
- [x] Help text documents the flag
## Done summary
Feature implementation completed:
1. --name flag parsing in _containai_run_cmd (containai.sh:1257-1272) and _containai_shell_cmd (containai.sh:837-852)
2. Custom name used if provided via _containai_start_container (container.sh:1192-1198)
3. Workspace validation via _containai_validate_fr4_mounts for both cai run and cai shell
4. Added workspace validation for existing containers in cai shell (containai.sh:1132-1150)
5. Help text documents the flag for both cai run (line 173) and cai shell (line 325)

## Evidence
- Commits: Current branch changes
- Tests: `cai --help` and `cai shell --help` show --name flag; FR-4 mount validation ensures workspace match
- PRs: N/A
