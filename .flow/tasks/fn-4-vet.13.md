# fn-4-vet.13 Delete aliases.sh and update tests

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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
