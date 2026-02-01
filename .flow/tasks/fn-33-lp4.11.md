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
## Implementation Summary

Added shell completion support for the `--template` option in both bash and zsh completions.

### Changes Made

1. **Bash Completion** (`src/containai.sh`):
   - Added helper function `_cai_completion_get_templates()` outside heredoc (line ~4955)
   - Added `--template` case in bash heredoc completion that lists directories from `~/.config/containai/templates/`
   - Removed `--template` from the "no completion" case

2. **Zsh Completion** (`src/containai.sh`):
   - Added helper function `_cai_get_templates()` inside zsh heredoc
   - Updated `--template` options for run, shell, and exec to use `->templates` state
   - Added `templates)` case in zsh state handler to describe template names

### Template Discovery
Both completion systems now scan `~/.config/containai/templates/` for subdirectories, using directory names as template names for completion.

### Commands Affected
- `cai run --template <TAB>` - now completes template names
- `cai shell --template <TAB>` - now completes template names
- `cai exec --template <TAB>` - now completes template names
## Notes
The `--template` parameter is now implemented (fn-33-lp4.9), so completions can be added.

## Evidence
- Commits:
- Tests:
- PRs:
