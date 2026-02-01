# fn-39-ua0.3 Dev tool sync tests

## Description
Test sync for dev tools: Git (with g-filter), GitHub CLI (secret separation), SSH (disabled/additional_paths), VS Code, tmux, vim/neovim.

**Size:** M
**Files:** `tests/integration/sync-tests/test-tool-sync.sh`

## Approach

### Tools to Test (from sync-manifest.toml)

| Tool | Entries | Flags | Notes |
|------|---------|-------|-------|
| Git | .gitconfig | fg | g flag strips credential.helper and signing config |
| Git | .gitignore_global | f | |
| GitHub CLI | hosts.yml | fs | Secret (OAuth tokens) |
| GitHub CLI | config.yml | f | Not secret |
| SSH | config, known_hosts, id_* | f/Gs, disabled=true | NOT synced by default |
| VS Code | extensions/, data/Machine/, data/User/mcp/, data/User/prompts/ | d | Non-optional, targets ensured |
| tmux | .tmux.conf (f), .config/tmux/ (d), .local/share/tmux/ (d) | f/d | |
| vim/neovim | .vimrc (f), .vim/ (dR), .config/nvim/ (dR) | f/dR | |
| Starship | .config/starship.toml | f | |
| Oh My Posh | .config/oh-my-posh/ | dR | |

<!-- Updated by plan-sync: fn-39-ua0.2 used run_cai_import_from and pattern matching, not run_import and assert_contains -->

### Git g-filter Test
```bash
test_git_filter() {
    # Create gitconfig with credential.helper and signing config
    cat > "$SYNC_TEST_FIXTURE_HOME/.gitconfig" <<'EOF'
[user]
    name = Test User
    email = test@example.com
[credential]
    helper = osxkeychain
[commit]
    gpgsign = true
[gpg]
    program = /usr/local/bin/gpg
EOF

    run_cai_import_from

    # Verify credential.helper and signing config stripped
    gitconfig=$(cat_from_volume "git/gitconfig")
    [[ "$gitconfig" == *"name = Test User"* ]] || return 1
    [[ "$gitconfig" != *"credential.helper"* ]] || return 1
    [[ "$gitconfig" != *"gpgsign"* ]] || return 1
    [[ "$gitconfig" != *"gpg"* ]] || return 1
}
```

### GitHub CLI Secret Separation Test
```bash
test_gh_secret_separation() {
    # hosts.yml is secret, config.yml is not
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/gh"
    echo "token: secret123" > "$SYNC_TEST_FIXTURE_HOME/.config/gh/hosts.yml"
    echo "editor: vim" > "$SYNC_TEST_FIXTURE_HOME/.config/gh/config.yml"

    run_cai_import_from

    # Both should sync
    assert_file_exists_in_volume "config/gh/hosts.yml" || return 1
    assert_file_exists_in_volume "config/gh/config.yml" || return 1

    # hosts.yml should have 600 perms
    assert_permissions_in_volume "config/gh/hosts.yml" "600" || return 1
    # config.yml should NOT have 600 perms (not secret)
    local config_perms
    config_perms=$(exec_in_container "$SYNC_TEST_CONTAINER" stat -c '%a' "/mnt/agent-data/config/gh/config.yml")
    [[ "$config_perms" != "600" ]] || return 1

    # With --no-secrets, only hosts.yml skipped
    run_cai_import_from --no-secrets
    assert_path_not_exists_in_volume "config/gh/hosts.yml" || return 1
    assert_file_exists_in_volume "config/gh/config.yml" || return 1
}
```

### SSH Disabled/additional_paths Test
```bash
test_ssh_disabled_by_default() {
    # Create SSH config in fixture
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.ssh"
    echo "Host *" > "$SYNC_TEST_FIXTURE_HOME/.ssh/config"

    run_cai_import_from

    # SSH should NOT be synced (disabled=true in manifest)
    assert_path_not_exists_in_volume "ssh" || return 1
}

test_ssh_via_additional_paths() {
    # Create containai.toml with additional_paths
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai"
    cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/containai.toml" <<'EOF'
[import]
additional_paths = ["~/.ssh"]
EOF

    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.ssh"
    echo "Host *" > "$SYNC_TEST_FIXTURE_HOME/.ssh/config"

    run_cai_import_from

    # SSH should now be synced
    assert_file_exists_in_volume "ssh/config" || return 1

    # NOTE: --no-secrets does NOT exclude additional_paths
    run_cai_import_from --no-secrets
    assert_file_exists_in_volume "ssh/config" || return 1
}
```

### VS Code Server Test (Non-Optional d Entries)
```bash
test_vscode_server_ensures_targets() {
    # VS Code entries are non-optional d flags
    # Even when source is missing, targets are ensured (empty dirs created)
    # Don't create any VS Code files in fixture

    run_cai_import_from

    # Directories should be ensured even when source missing
    # ensure() is called for non-optional d entries
    assert_path_exists_in_volume "vscode-server/extensions" || return 1
    assert_path_exists_in_volume "vscode-server/data/Machine" || return 1
    assert_path_exists_in_volume "vscode-server/data/User/mcp" || return 1
}

test_vscode_server_syncs_content() {
    # When source exists, content syncs
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.vscode-server/extensions/test-ext"
    echo '{}' > "$SYNC_TEST_FIXTURE_HOME/.vscode-server/extensions/test-ext/package.json"

    run_cai_import_from

    assert_file_exists_in_volume "vscode-server/extensions/test-ext/package.json" || return 1
}
```

### tmux/vim Tests

Volume target paths from sync-manifest.toml:
- `.tmux.conf` -> `config/tmux/tmux.conf`
- `.config/tmux/` -> `config/tmux/`
- `.local/share/tmux/` -> `local/share/tmux/`
- `.vimrc` -> `editors/vimrc`
- `.vim/` -> `editors/vim/`
- `.config/nvim/` -> `config/nvim/`

```bash
test_tmux_sync() {
    # Legacy .tmux.conf syncs to config/tmux/tmux.conf
    echo 'set -g mouse on' > "$SYNC_TEST_FIXTURE_HOME/.tmux.conf"
    # XDG .config/tmux syncs to config/tmux
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/tmux"
    echo 'source-file ~/.tmux.conf' > "$SYNC_TEST_FIXTURE_HOME/.config/tmux/tmux.conf"

    run_cai_import_from

    # Legacy tmux.conf -> config/tmux/tmux.conf
    assert_file_exists_in_volume "config/tmux/tmux.conf" || return 1
    # XDG config/tmux -> config/tmux (same target, XDG wins)
    content=$(cat_from_volume "config/tmux/tmux.conf")
    # XDG should overwrite legacy since it syncs second
    [[ "$content" == *"source-file"* ]] || return 1
}

test_vim_sync() {
    echo 'set number' > "$SYNC_TEST_FIXTURE_HOME/.vimrc"
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.vim/colors"
    echo 'colorscheme test' > "$SYNC_TEST_FIXTURE_HOME/.vim/colors/test.vim"
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/nvim"
    echo 'set termguicolors' > "$SYNC_TEST_FIXTURE_HOME/.config/nvim/init.vim"

    run_cai_import_from

    # .vimrc -> editors/vimrc
    assert_file_exists_in_volume "editors/vimrc" || return 1
    # .vim/ -> editors/vim/
    assert_file_exists_in_volume "editors/vim/colors/test.vim" || return 1
    # .config/nvim/ -> config/nvim/
    assert_file_exists_in_volume "config/nvim/init.vim" || return 1
}

test_starship_sync() {
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config"
    echo 'format = "$all"' > "$SYNC_TEST_FIXTURE_HOME/.config/starship.toml"

    run_cai_import_from

    assert_file_exists_in_volume "config/starship.toml" || return 1
}

test_ohmyposh_sync() {
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/oh-my-posh"
    echo '{}' > "$SYNC_TEST_FIXTURE_HOME/.config/oh-my-posh/theme.json"

    run_cai_import_from

    assert_file_exists_in_volume "config/oh-my-posh/theme.json" || return 1
}
```

## Key context

- g flag: Git config filtering is critical for security
- SSH is disabled by default; opt-in via additional_paths only
- --no-secrets does NOT affect additional_paths (explicit user choice)
- VS Code Server entries are non-optional `d` - targets ensured even when source missing
- ensure() is called for missing non-optional d entries

## Acceptance
- [ ] Git g-filter tested (credential.helper stripped)
- [ ] Git g-filter tested (signing config stripped)
- [ ] GitHub CLI secret separation (hosts.yml vs config.yml)
- [ ] SSH disabled by default verified
- [ ] SSH additional_paths opt-in tested
- [ ] --no-secrets does not affect additional_paths
- [ ] VS Code Server: targets ensured when source missing
- [ ] VS Code Server: content syncs when source exists
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
