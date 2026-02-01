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
Added --template parameter to run/shell/exec commands with template mismatch validation for existing containers, proper precedence over --image-tag, and dry-run support.
## Evidence
- Commits: 17b0ec58f26eabb705966bcadbb8ba3a0835a813, 6b61fcea844915ffa94ae4d9d7ee9de42f2c9be9, 069e76e7d87ea9a33a9efe0b70bb2e78d99b8e5f
- Tests: shellcheck -x src/containai.sh src/lib/container.sh
- PRs:
