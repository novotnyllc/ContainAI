# fn-39-ua0 Comprehensive Sync System E2E Tests

## Overview

Create comprehensive E2E tests for the sync system. Tests validate that `cai import` and `cai export` work correctly for all agents/tools defined in sync-manifest.toml.

Tests run from user perspective: build container, use `--from <mock-home>` to import test fixtures, verify sync behavior.

## Key Implementation Details

### Import Behavior (from src/lib/import.sh)
- **Profile import** (`source_root == $HOME`): Secret files are skipped, only placeholders with 600 perms created
- **--from import** (`source_root != $HOME`): Full content sync including secrets
- **Optional (`o` flag)**: Missing sources are skipped entirely - no target creation
- **JSON init (`j` flag)**: Creates `{}` for empty/missing files, but only if not optional
- **Secret (`s` flag)**: Sets 600 perms on files, 700 on directories; skipped with `--no-secrets`
- **Remove first (`R` flag)**: rm -rf existing path before symlink creation (for container links)
- **Exclude system (`x` flag)**: Excludes `.system/` subdirectory from sync
- **Priv filter (`p` flag)**: Excludes `*.priv.*` files (security - .bashrc.d)
- **Git filter (`g` flag)**: Strips credential.helper and signing config from .gitconfig
- **Disabled entries**: Not in sync map but generate links (e.g., SSH - opt-in via additional_paths)

### Shell Customization Paths
- `.bash_aliases` → syncs to `shell/bash_aliases`, linked as `~/.bash_aliases_imported`
- `.bashrc.d/` → syncs to `shell/bashrc.d`, sourced from `/mnt/agent-data/shell/bashrc.d`
- Container `.bashrc` has hooks that source both locations

### Test Infrastructure Reuse
Tests should reuse/extend helpers from existing `tests/integration/test-sync-integration.sh`:
- Docker context selection (DinD vs host)
- Safe cleanup with labels
- Hermetic HOME/DOCKER_CONFIG preservation

## Scope

### AI Agents (sync-manifest.toml entries)

| Agent | Source Prefix | Key Entries | Notes |
|-------|---------------|-------------|-------|
| Claude Code | ~/.claude/ | .claude.json (fjs), .credentials.json (fs), settings.json (fj), commands/, agents/, skills/, plugins/, hooks/, CLAUDE.md | Profile import skips secrets |
| OpenCode | ~/.config/opencode/ + ~/.local/share/opencode/ | opencode.json (fjs), auth.json (fs), agents/, commands/, skills/, modes/, plugins/, instructions.md | auth.json at ~/.local/share/opencode/ |
| Codex | ~/.codex/ | config.toml (f), auth.json (fs), skills (dxR) | x flag excludes .system/ |
| Copilot | ~/.copilot/ | config.json (fo), mcp-config.json (fo), skills (dRo) | All optional |
| Gemini | ~/.gemini/ | google_accounts.json (fso), oauth_creds.json (fso), settings.json (fjo), GEMINI.md (fo) | All optional |
| Aider | ~/ | .aider.conf.yml (fso), .aider.model.settings.yml (fso) | Optional secrets |
| Continue | ~/.continue/ | config.yaml (fso), config.json (fjso) | Optional |
| Cursor | ~/.cursor/ | mcp.json (fjso), rules (dRo), extensions (dRo) | Optional |
| Pi | ~/.pi/agent/ | settings.json (fjo), models.json (fjso), keybindings.json (fjo), skills (dxRo), extensions (dRo) | Optional |
| Kimi | ~/.kimi/ | config.toml (fso), mcp.json (fjso) | Optional |

### Dev Tools

| Tool | Source | Flags | Notes |
|------|--------|-------|-------|
| Git | ~/.gitconfig | fg | g flag strips credential.helper/signing |
| Git | ~/.gitignore_global | f | |
| GitHub CLI | ~/.config/gh/hosts.yml | fs | Secret (OAuth tokens) |
| GitHub CLI | ~/.config/gh/config.yml | f | |
| SSH | ~/.ssh/* | disabled | Opt-in via additional_paths only |
| VS Code Server | ~/.vscode-server/* | d | extensions/, data/Machine/, data/User/mcp/ |
| tmux | ~/.tmux.conf, ~/.config/tmux/, ~/.local/share/tmux/ | f/d | |
| vim/neovim | ~/.vimrc, ~/.vim/, ~/.config/nvim/ | f/dR | |

### Shell Customization

| Entry | Source | Target | Container Path | Flags |
|-------|--------|--------|----------------|-------|
| bash_aliases | ~/.bash_aliases | shell/bash_aliases | ~/.bash_aliases_imported | fR |
| bashrc.d | ~/.bashrc.d/ | shell/bashrc.d | /mnt/agent-data/shell/bashrc.d | dp |
| zshrc | ~/.zshrc | shell/zshrc | ~/.zshrc | f |
| zprofile | ~/.zprofile | shell/zprofile | ~/.zprofile | f |
| zshenv | ~/.zshenv | shell/zshenv | ~/.zshenv | f |
| inputrc | ~/.inputrc | shell/inputrc | ~/.inputrc | f |
| oh-my-zsh/custom | ~/.oh-my-zsh/custom | shell/ohmyzsh-custom | ~/.oh-my-zsh/custom | dR |

### Other

- ~/.agents/ - shared agent configuration (d)
- ~/.local/share/fonts/ - custom fonts (d)
- ~/.config/starship.toml - Starship prompt (f)
- ~/.config/oh-my-posh/ - Oh My Posh themes (dR)

## Test Approach

### Categories

1. **Agent Import Tests** - For each agent, create fixture, use `--from`, verify sync
2. **Tool Import Tests** - Git (with g filter), gh (secret vs non-secret), VS Code
3. **Shell Import Tests** - Test .bashrc.d sourcing via `bash -i -c`, aliases via ~/.bash_aliases_imported
4. **Flag Behavior Tests** - Test specific flag behaviors (not CLI flags)
5. **CLI Option Tests** - --dry-run, --no-secrets, --from
6. **Edge Case Tests** - Optional entries, partial configs, priv filter

### Test Structure

Extend existing test-sync-integration.sh or create modular test files:
```
tests/integration/test-sync-e2e.sh           # Main orchestrator
tests/integration/sync-test-helpers.sh       # Extracted from test-sync-integration.sh
tests/integration/sync-tests/
├── test-agent-sync.sh                       # All AI agents
├── test-tool-sync.sh                        # Dev tools
├── test-shell-sync.sh                       # Shell customization
├── test-flags.sh                            # Flag behaviors
└── test-edge-cases.sh                       # Edge cases
```

## Tasks

### fn-39-ua0.1: Test infrastructure setup
- Extract reusable helpers from test-sync-integration.sh
- Create mock HOME fixture generator
- Container management (build, run with --from, cleanup)
- Assertion helpers for file existence, permissions, content

### fn-39-ua0.2: AI agent sync tests
For each agent:
- Create fixture with test files
- Run import with `--from <fixture>`
- Verify files sync to correct target paths
- Verify symlinks created correctly
- Test profile-import behavior (secrets become placeholders)
- Test optional agents (missing source = no target)

### fn-39-ua0.3: Dev tool sync tests
- Git: test g flag strips credential.helper/signing
- GitHub CLI: test secret separation (hosts.yml vs config.yml)
- SSH: test disabled=true behavior, additional_paths opt-in
- VS Code: test extensions/, data/Machine/, data/User/mcp/
- tmux/vim: basic sync verification

### fn-39-ua0.4: Shell customization tests
- .bashrc.d: verify files land in /mnt/agent-data/shell/bashrc.d
- .bashrc.d: verify sourced via `bash -i -c 'env'` (create test script setting var)
- .bashrc.d: verify p flag excludes *.priv.* files
- .bash_aliases: verify linked as ~/.bash_aliases_imported
- .inputrc: verify file syncs and is readable
- oh-my-zsh/custom: verify sync with R flag

### fn-39-ua0.5: Flag and operation tests
**Flag tests (manifest flags, not CLI):**
- `j`: Test non-optional fj entry (e.g., .claude/settings.json) - empty creates {}
- `s`: Test 600/700 permissions on secret files/dirs
- `R`: Test symlink replacement when pre-existing dir conflicts
- `x`: Test .system/ exclusion for Codex/Pi skills
- `p`: Test *.priv.* exclusion in .bashrc.d
- `g`: Test credential.helper stripping in .gitconfig
- `o`: Test optional entries - missing source = no target created

**CLI operation tests:**
- `--dry-run`: Verify [DRY-RUN] markers, volume unchanged
- `--no-secrets`: Verify s-flagged entries skipped entirely
- Profile import vs --from import behavior

### fn-39-ua0.6: Edge case tests
- No pollution: optional agent roots (Pi, Kimi, etc.) not created when missing
- Partial config: some files exist, others don't
- Large directories: fonts with many files
- Symlink relinking: internal symlinks remapped correctly
- additional_paths: test opt-in for SSH

## Quick Commands

```bash
# Run all sync E2E tests
./tests/integration/test-sync-e2e.sh

# Run specific module
./tests/integration/test-sync-e2e.sh --only agents
./tests/integration/test-sync-e2e.sh --only shell
./tests/integration/test-sync-e2e.sh --only flags

# Build container first
./src/build.sh
```

## Acceptance Criteria

- [ ] Test helpers extracted/created (reuse test-sync-integration.sh patterns)
- [ ] All 10 AI agents tested with --from import
- [ ] Dev tools tested (Git g-filter, gh secret separation, VS Code)
- [ ] Shell customization tested (bash -i -c sourcing, correct paths)
- [ ] All manifest flags tested (j, s, R, x, p, g, o)
- [ ] CLI options tested (--dry-run, --no-secrets, profile vs --from)
- [ ] No-pollution verified for optional entries
- [ ] All tests pass: ./tests/integration/test-sync-e2e.sh

## Dependencies

- **fn-35-e0x**: Pi & Kimi sync entries must be added first

## References

- sync-manifest.toml: src/sync-manifest.toml
- Import logic: src/lib/import.sh (profile credential handling, flag behaviors)
- Existing sync tests: tests/integration/test-sync-integration.sh
- Container bashrc hooks: src/container/Dockerfile.agents
