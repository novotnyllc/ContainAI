# fn-36-rb7.10 Update cai setup to install shell completions

## Description
Update `cai setup` to install **static** completion scripts (no eval at shell startup).

## Acceptance
- [ ] Bash: writes `~/.bashrc.d/containai-completion.bash` if `~/.bashrc.d/` exists
- [ ] Bash: otherwise appends source line to `~/.bashrc`
- [ ] Zsh: writes `~/.zsh/completions/_cai`
- [ ] Ensures `fpath` includes `~/.zsh/completions`
- [ ] Script is static (no `eval "$(cai completion bash)"`)
- [ ] Creates parent directories if needed
- [ ] Logs where completion was installed

## Verification
- [ ] Run `cai setup`, start new shell, verify `cai <TAB>` works

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
