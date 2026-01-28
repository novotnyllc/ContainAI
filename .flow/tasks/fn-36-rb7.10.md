# fn-36-rb7.10 Update cai setup to install shell completions

## Description
Add completion script installation to `cai setup`:
- For bash: Create `~/.bashrc.d/containai-completion.sh` if `.bashrc.d/` exists, otherwise add to `~/.bashrc`
- For zsh: Create `~/.zsh/completions/_cai` and ensure fpath includes it
- Completion file should contain: `eval "$(cai completion bash)"` (or zsh equivalent)

## Acceptance
- [ ] `cai setup` creates completion file for bash
- [ ] `cai setup` creates completion file for zsh if zsh detected
- [ ] Completions work immediately after setup (new shell session)
- [ ] Existing completion setups are not duplicated

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
