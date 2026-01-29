# fn-39-ua0 Comprehensive Sync System E2E Tests

## Overview

Create comprehensive E2E tests for the entire sync system. Test ALL agents and tools in sync-manifest.toml, shell customization (.bashrc.d), and all flag combinations.

Tests run from user perspective: build container, create mock HOME with test configs, run cai import/export, verify everything syncs correctly.

## Scope

### In Scope

**10 AI Agents:**
| Agent | Config Location | Key Files |
|-------|-----------------|-----------|
| Claude Code | ~/.claude/ | .credentials.json (s), settings.json, plugins/, skills/, hooks/ |
| Gemini | ~/.gemini/ | google_accounts.json (s), oauth_creds.json (s), settings.json |
| Codex | ~/.codex/ | config.toml, auth.json (s), skills/ |
| Copilot | ~/.copilot/ | config.json, mcp-config.json, skills/ |
| OpenCode | ~/.config/opencode/ | opencode.json, auth.json (s), agents/, commands/ |
| Aider | ~/ | .aider.conf.yml, .aider.model.settings.yml |
| Continue | ~/.continue/ | config.yaml, config.json |
| Cursor | ~/.cursor/ | mcp.json, rules/, extensions/ |
| Pi | ~/.pi/agent/ | settings.json, models.json (s), skills/, extensions/ |
| Kimi | ~/.kimi/ | config.toml (s), mcp.json (s) |

**6 Dev Tools:**
| Tool | Config Location | Key Files |
|------|-----------------|-----------|
| Git | ~/ | .gitconfig, .gitignore_global |
| GitHub CLI | ~/.config/gh/ | hosts.yml (s), config.yml |
| SSH | ~/.ssh/ | config, known_hosts, id_* (s) |
| VS Code Server | ~/.vscode-server/ | extensions/, data/Machine/, data/User/mcp/ |
| tmux | ~/ | .tmux.conf, .config/tmux/, .local/share/tmux/ |
| vim/neovim | ~/ | .vimrc, .vim/, .config/nvim/ |

**Shell Customization:**
- .bashrc.d/ - custom shell scripts (MUST source on login)
- .bash_aliases - alias definitions
- .zshrc, .zprofile - zsh configs
- .inputrc - readline config
- .oh-my-zsh/custom - oh-my-zsh customizations

**Other:**
- ~/.agents/ - shared agent configuration
- ~/.local/share/fonts/ - custom fonts
- Starship, Oh My Posh prompt configs

### Out of Scope
- Modifying sync logic (testing only)
- Adding new agents (that's fn-35-e0x)
- Performance benchmarks

## Approach

### Test Categories

1. **Import Tests** - host → container for each agent/tool
2. **Export Tests** - container → host
3. **Shell Tests** - .bashrc.d sourced, aliases work
4. **Flag Tests** - s, j, R, x flags behave correctly
5. **Dry-Run Tests** - --dry-run shows but doesn't change
6. **Edge Cases** - no config, partial config, large dirs

### Test Structure

```
tests/integration/test-sync-e2e.sh      # Main test runner
tests/integration/sync-tests/           # Test modules
├── test-agent-sync.sh                  # All AI agents
├── test-tool-sync.sh                   # Dev tools (git, gh, ssh, etc)
├── test-shell-sync.sh                  # .bashrc.d, aliases, etc
├── test-flags.sh                       # Flag behavior tests
└── test-edge-cases.sh                  # Edge cases
```

## Tasks

### fn-39-ua0.1: Test infrastructure setup
Create test harness, mock HOME setup, container management helpers.

### fn-39-ua0.2: AI agent sync tests
Test all 10 AI agents: Claude, Gemini, Codex, Copilot, OpenCode, Aider, Continue, Cursor, Pi, Kimi.

### fn-39-ua0.3: Dev tool sync tests
Test Git, GitHub CLI, SSH, VS Code Server, tmux, vim/neovim, Starship, Oh My Posh.

### fn-39-ua0.4: Shell customization tests
Test .bashrc.d sourcing, .bash_aliases, .inputrc, zsh configs, oh-my-zsh.

### fn-39-ua0.5: Flag and operation tests
Test all flags (s, j, R, x), --no-secrets, import, export, dry-run modes.

### fn-39-ua0.6: Edge case tests
Test no-config pollution, partial configs, large directories, concurrent containers.

## Quick commands

```bash
# Run all sync tests
./tests/integration/test-sync-e2e.sh

# Run specific test module
./tests/integration/test-sync-e2e.sh --only agents
./tests/integration/test-sync-e2e.sh --only shell
./tests/integration/test-sync-e2e.sh --only flags

# Build container first
./src/build.sh
```

## Acceptance

- [ ] Test infrastructure created (mock HOME, container helpers)
- [ ] All 10 AI agents tested for sync
- [ ] All 6 dev tools tested for sync
- [ ] Shell customization tested (.bashrc.d sourced on login)
- [ ] All flags tested (s, j, R, x)
- [ ] --no-secrets option tested
- [ ] Import and export operations tested
- [ ] Dry-run modes tested
- [ ] Edge cases tested (no pollution, partial config)
- [ ] All tests pass: ./tests/integration/test-sync-e2e.sh

## Dependencies

- **fn-35-e0x**: Pi & Kimi sync entries must be added first

## References

- sync-manifest.toml: src/sync-manifest.toml
- Existing sync tests: tests/integration/test-sync-integration.sh
- Import logic: src/lib/import.sh
