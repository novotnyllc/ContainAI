# Task fn-51.1: Create per-agent manifest directory structure and split sync-manifest.toml

**Status:** pending
**Depends on:** none

## Objective

Split the monolithic `src/sync-manifest.toml` into per-agent files in `src/manifests/`.

## Context

The current `sync-manifest.toml` (628 lines) mixes all agents/tools together. Splitting allows:
- Easier maintenance per agent
- Clear ownership boundaries
- User-extensible via additional manifest files

## Implementation

1. Create directory `src/manifests/`

2. Split into these files (based on current section headers in sync-manifest.toml):
   - `claude.toml` - Claude Code entries (lines 37-99)
   - `gh.toml` - GitHub CLI entries (lines 101-120)
   - `git.toml` - Git config entries (lines 122-140)
   - `ssh.toml` - SSH entries, disabled (lines 142-175)
   - `opencode.toml` - OpenCode entries (lines 177-229)
   - `tmux.toml` - tmux entries (lines 231-253)
   - `common.toml` - Fonts, agents directory (lines 255-273)
   - `shell.toml` - Shell config entries (lines 275-319)
   - `editors.toml` - Vim/Neovim entries (lines 321-341)
   - `prompt.toml` - Starship/oh-my-posh (lines 343-357)
   - `vscode.toml` - VS Code Server entries (lines 359-413)
   - `copilot.toml` - Copilot entries, optional (lines 415-435)
   - `gemini.toml` - Gemini entries, optional (lines 437-463)
   - `codex.toml` - Codex entries (lines 465-485)
   - `aider.toml` - Aider entries, optional (lines 487-503)
   - `continue.toml` - Continue entries, optional (lines 505-521)
   - `cursor.toml` - Cursor entries, optional (lines 523-545)
   - `pi.toml` - Pi entries, optional (lines 547-581)
   - `kimi.toml` - Kimi entries, optional (lines 583-600)

3. Each file includes header comment with agent name and docs link

4. Preserve all existing entries, flags, comments exactly

5. Add `[[container_symlinks]]` entries to appropriate agent files (currently at end of manifest)

## Acceptance Criteria

- [ ] `src/manifests/` directory created with 19 files
- [ ] Each file contains only entries for that agent/tool
- [ ] All entries from original manifest preserved (no content lost)
- [ ] Header comments preserved with agent name
- [ ] `cat src/manifests/*.toml` produces equivalent content to original
- [ ] Original `sync-manifest.toml` untouched (for now)

## Notes

- Do NOT modify `_IMPORT_SYNC_MAP` in import.sh yet
- Do NOT delete `sync-manifest.toml` yet
- Aggregation script (Task 3) will combine these files
