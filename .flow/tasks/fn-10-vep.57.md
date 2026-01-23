# fn-10-vep.57 Support --data-volume flag for custom volume names

## Description
Support `--data-volume` flag for custom data volume names.

**Size:** S
**Files:** lib/container.sh

## Approach

1. Add `--data-volume` flag to run/shell commands
2. Precedence: CLI flag > config.toml > default
3. Store selected volume in container label for consistency
4. Default: `containai-data-{workspace-hash}`

## Key context

- Matches existing fn-4-vet volume handling patterns
- Label: `containai.data-volume` already defined in spec
## Acceptance
- [ ] `--data-volume` flag added to `cai run` and `cai shell`
- [ ] Precedence: CLI > config.toml > default
- [ ] Volume name stored in container label
- [ ] Existing containers with different volume error without `--fresh`
- [ ] Help text documents the flag
## Done summary
Added `containai.data-volume` label to container creation. The `--data-volume` flag was already implemented in `cai run` and `cai shell` commands with proper precedence (CLI > config.toml > default). Volume mismatch checking was already implemented to error when existing containers have different volumes unless `--fresh` is used.
## Evidence
- Commits:
- Tests: bash -n src/lib/container.sh, shellcheck -x src/lib/container.sh
- PRs:
