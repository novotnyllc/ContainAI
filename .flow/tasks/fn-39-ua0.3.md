# fn-39-ua0.3 Dev tool sync tests

## Description
Test sync for dev tools: Git, GitHub CLI, SSH, VS Code Server, tmux, vim/neovim, Starship, Oh My Posh.

**Size:** M
**Files:** `tests/integration/sync-tests/test-tool-sync.sh`

## Approach

### Tools to Test

| Tool | Test Files | Secret Files | Notes |
|------|------------|--------------|-------|
| Git | .gitconfig, .gitignore_global | - | |
| GitHub CLI | config.yml | hosts.yml | |
| SSH | config, known_hosts | id_* | Disabled by default |
| VS Code | extensions/, data/Machine/ | - | Only if installed |
| tmux | .tmux.conf, .config/tmux/ | - | |
| vim | .vimrc, .vim/, .config/nvim/ | - | |
| Starship | starship.toml | - | |
| Oh My Posh | oh-my-posh/ | - | |

### SSH Special Handling
SSH entries are disabled by default in sync-manifest.toml. Test should:
1. Verify disabled entries are NOT synced by default
2. Test that enabling works (if mechanism exists)

### Test Structure
```bash
test_git_sync() {
    create_mock_gitconfig
    run_import
    assert_file_exists_in_container "~/.gitconfig"
    exec_in_container git config --global user.name  # Verify readable
}
```

## Key context

- SSH has `disabled = true` in manifest
- VS Code Server only exists if user has connected via VS Code
- fonts/ can be large - test with small mock
## Acceptance
- [ ] Git config sync tested
- [ ] GitHub CLI sync tested (hosts.yml secret)
- [ ] SSH sync tested (respects disabled flag)
- [ ] VS Code Server sync tested (graceful skip if not present)
- [ ] tmux sync tested
- [ ] vim/neovim sync tested
- [ ] Starship sync tested
- [ ] Oh My Posh sync tested
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
