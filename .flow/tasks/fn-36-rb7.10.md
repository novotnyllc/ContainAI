# fn-36-rb7.10 Update cai setup to install shell completions

## Description
Update `cai setup` to install **static** completion scripts (no eval at shell startup).

## Acceptance
- [x] Bash: writes `~/.bashrc.d/containai-completion.bash` if `~/.bashrc.d/` exists
- [x] Bash: otherwise appends source line to `~/.bashrc`
- [x] Zsh: writes `~/.zsh/completions/_cai`
- [x] Ensures `fpath` includes `~/.zsh/completions`
- [x] Script is static (no `eval "$(cai completion bash)"`)
- [x] Creates parent directories if needed
- [x] Logs where completion was installed

## Verification
- [x] Run `cai setup`, start new shell, verify `cai <TAB>` works

## Done summary
Implemented static shell completion installation in `cai setup`:
- Added `_cai_setup_shell_completions()` function to `src/lib/setup.sh`
- Bash: writes to `~/.bashrc.d/containai-completion.bash` if dir exists, otherwise to `~/.local/share/bash-completion/completions/cai` with source line in `~/.bashrc`
- Zsh: writes to `~/.zsh/completions/_cai` and updates fpath in `~/.zshrc` (preserves symlinks, handles symlinked .zshrc)
- Creates parent directories as needed
- Logs installation locations
- Integrated into setup flow for all platforms (Linux, macOS, WSL, nested container)
- Script is static (no eval at shell startup)
## Evidence
- Commits: b3ca96f2cb048675d4d0e04c5e4071f85daacf97
- Tests: cai setup --dry-run, shellcheck -x src/lib/setup.sh
- PRs:
