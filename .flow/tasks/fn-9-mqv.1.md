# fn-9-mqv.1 Add --from flag to import CLI

## Description
Add `--from <path>` flag to the import CLI command handler.

**Size:** S
**Files:** `agent-sandbox/containai.sh`

## Approach

- Follow CLI pattern at `containai.sh:427-529` (`_containai_import_cmd`)
- Add `--from` to argument parsing `while` loop (around line 460)
- Pass source path to `_containai_import()` as new parameter
- Update help text at `containai.sh:213-233` (`_containai_import_help`)

## Key context

- Current pattern uses positional args + flags parsed in `while/case`
- Volume is resolved via `_containai_resolve_volume` after arg parsing
- Pass empty string for `--from` to mean "use default $HOME"
## Acceptance
- [ ] `cai import <vol> --from /path` accepted without error
- [ ] `cai import --help` shows `--from` flag documentation
- [ ] `--from` value passed to `_containai_import()` function
- [ ] Existing `cai import <vol>` (no --from) still works
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
