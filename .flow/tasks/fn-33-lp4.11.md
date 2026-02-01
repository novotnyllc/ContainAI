# fn-33-lp4.11 Update shell completions

## Description
Add `--template` to completion lists for run/shell/exec commands. Update both bash and zsh completions in `src/containai.sh`.

## Acceptance
- [ ] `--template` in bash completion for `cai run`
- [ ] `--template` in bash completion for `cai shell`
- [ ] `--template` in bash completion for `cai exec`
- [ ] `--template` in zsh completion for `cai run`
- [ ] `--template` in zsh completion for `cai shell`
- [ ] `--template` in zsh completion for `cai exec`
- [ ] Template name completion from `~/.config/containai/templates/` directory

## Done summary
TBD

## Notes
**Blocked on fn-33-lp4.9**: Shell completions should not advertise `--template` until the parameter parsing is implemented. During review, adding completions for non-existent flags was flagged as misleading to users.

## Evidence
- Commits:
- Tests:
- PRs:
