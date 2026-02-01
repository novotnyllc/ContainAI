# fn-33-lp4.9 Add --template parameter

## Description
Add `--template` parameter to `run`, `shell`, `exec` commands. Coexists with `--image-tag` (different semantics). Template mismatch with existing container errors with `--fresh` guidance.

## Acceptance
- [ ] `--template <name>` flag added to run/shell/exec
- [ ] `--template` takes priority over `--image-tag` for image selection
- [ ] Warning emitted if both `--template` and `--image-tag` provided
- [ ] Container stores template in label `ai.containai.template`
- [ ] Missing label (pre-existing container): allow if `--template default`, else error
- [ ] Label mismatch: error "Container exists with template 'X'. Use --fresh to rebuild."
- [ ] `--template` documented in `cai run --help` output
- [ ] Works with `--dry-run` showing template build step

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
