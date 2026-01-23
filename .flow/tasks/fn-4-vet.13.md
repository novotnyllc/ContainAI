# fn-4-vet.13 Delete aliases.sh and update tests

<!-- Updated by plan-sync: fn-4-vet.4 architecture note -->
<!-- WARNING: aliases.sh contains ALL implementation - config, container, main functions -->
<!-- Cannot delete until lib extraction (fn-4-vet.8/9) AND containai.sh (fn-4-vet.12) are complete -->
<!-- Ensure containai.sh properly replaces all aliases.sh functionality before deletion -->

## Description
Delete `aliases.sh` and update integration tests.

## Files to Delete
- `agent-sandbox/aliases.sh` - replaced by containai.sh + lib/
- `agent-sandbox/sync-agent-plugins.sh` - replaced by `cai import`

## Test Updates

Update `agent-sandbox/test-sync-integration.sh`:
1. Source `containai.sh` instead of `aliases.sh`
2. Use `cai import --dry-run` instead of `sync-agent-plugins.sh --dry-run`
3. Use test-specific volume via `--data-volume test-volume`
4. Update any `asb*` references to `cai*`

## Documentation Updates

Update any README or docs that reference:
- `asb` → `cai` / `containai`
- `sync-agent-plugins.sh` → `cai import`
- Old config paths

## Verification

After deletion, ensure:
```bash
source agent-sandbox/containai.sh
cai --help
cai import --dry-run
```
## Acceptance
- [ ] `agent-sandbox/aliases.sh` deleted
- [ ] `agent-sandbox/sync-agent-plugins.sh` deleted
- [ ] `test-sync-integration.sh` updated to use new CLI
- [ ] All tests pass with new CLI
- [ ] No remaining references to `asb*` in codebase
- [ ] `cai --help` works
- [ ] `cai import --dry-run` works
## Done summary
Deleted aliases.sh and sync-agent-plugins.sh, updated test-sync-integration.sh to use cai import, removed legacy label support from container.sh, and cleaned up documentation.
## Evidence
- Commits: 06258db501a4b2add072303b6c01a611f30ca305, 8bb4faa7b1809609e9f27be3a522ec018b4cdde7, 9e7d08a44196c2f44a2f0eb8a300676e484fa044, dff802f5fd03a3280431b1ac2f088372a46626fd
- Tests: bash -c 'cd agent-sandbox && source containai.sh && cai --help', bash -c 'cd agent-sandbox && source containai.sh && cai import --dry-run'
- PRs:
