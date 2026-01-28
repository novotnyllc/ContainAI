# fn-36-rb7.8 Implement shell completion for cai commands

## Description
Add `cai completion bash` and `cai completion zsh` that output static completion scripts. Ensure `completion` bypasses update checks and is fast.

## Acceptance
- [ ] `cai completion bash` outputs full bash completion script
- [ ] `cai completion zsh` outputs full zsh completion script
- [ ] Completes subcommands: shell, run, exec, import, export, stop, status, gc, doctor, config, docker
- [ ] Completes flags per subcommand
- [ ] Dynamic completion for `--container` and `--data-volume` only
- [ ] Uses 5s cache for docker-derived values
- [ ] Docker lookup timeout >500ms falls back to no suggestions
- [ ] Fast (<100ms), no update checks, no network I/O
- [ ] `completion` added to update-check skip list
- [ ] Script is static and can be saved to file

## Verification
- [ ] `source <(cai completion bash)` and verify `cai <TAB>`
- [ ] Verify no network calls and no update check on completion

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
