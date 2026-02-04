# Task fn-51.1: Create per-agent manifest directory structure and split sync-manifest.toml

**Status:** pending
**Depends on:** none

## Objective

Split the monolithic `src/sync-manifest.toml` into per-agent files in `src/manifests/` with numeric prefixes for deterministic ordering.

## Context

The current `sync-manifest.toml` (628 lines) mixes all agents/tools together. Splitting allows:
- Easier maintenance per agent
- Clear ownership boundaries
- User-extensible via additional manifest files
- Deterministic generator output via sorted iteration

## Implementation

1. Create directory `src/manifests/`

2. Split into these files with numeric prefixes (preserving original section order):
   - `00-common.toml` - Fonts, agents directory (lines 255-273)
   - `01-shell.toml` - Shell config entries (lines 275-319)
   - `02-git.toml` - Git config entries (lines 122-140)
   - `03-gh.toml` - GitHub CLI entries (lines 101-120)
   - `04-editors.toml` - Vim/Neovim entries (lines 321-341)
   - `05-vscode.toml` - VS Code Server entries + container_symlinks (lines 359-413, plus container_symlinks section)
   - `06-ssh.toml` - SSH entries, disabled (lines 142-175)
   - `07-tmux.toml` - tmux entries (lines 231-253)
   - `08-prompt.toml` - Starship/oh-my-posh (lines 343-357)
   - `10-claude.toml` - Claude Code entries (lines 37-99)
   - `11-codex.toml` - Codex entries (lines 465-485)
   - `12-gemini.toml` - Gemini entries, optional (lines 437-463)
   - `13-copilot.toml` - Copilot entries, optional (lines 415-435)
   - `14-opencode.toml` - OpenCode entries (lines 177-229)
   - `15-kimi.toml` - Kimi entries, optional (lines 583-600)
   - `16-pi.toml` - Pi entries, optional (lines 547-581)
   - `17-aider.toml` - Aider entries, optional (lines 487-503)
   - `18-continue.toml` - Continue entries, optional (lines 505-521)
   - `19-cursor.toml` - Cursor entries, optional (lines 523-545)

3. Move existing section headers verbatim (do NOT add new comments or doc links)

4. Move all existing entries, flags exactly - copy-paste, do not modify

5. `[[container_symlinks]]` entries go in `05-vscode.toml` (they are VS Code related)

## Acceptance Criteria

- [ ] `src/manifests/` directory created with ~20 files
- [ ] Numeric prefixes ensure sorted iteration matches original order
- [ ] Each file contains only entries for that agent/tool
- [ ] All entries from original manifest preserved (no content lost)
- [ ] Existing comments/section headers moved verbatim (no new prose added)
- [ ] `[[container_symlinks]]` in `05-vscode.toml`
- [ ] Original `sync-manifest.toml` untouched (for verification)

## Notes

- Numeric prefixes: 00-09 for infrastructure, 10+ for agents
- Do NOT modify `_IMPORT_SYNC_MAP` in import.sh yet (Task 3 handles this)
- Do NOT delete `sync-manifest.toml` yet (deleted in Task 3 after verification)
- Do NOT add new comments, doc links, or headers - just move existing content
