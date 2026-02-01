# fn-39-ua0.4 Shell customization tests

## Description
Test shell customization sync: .bashrc.d sourcing (correct paths), aliases via ~/.bash_aliases_imported, inputrc, zsh configs.

**Size:** M
**Files:** `tests/integration/sync-tests/test-shell-sync.sh`

## Approach

### Critical Path Details (from sync-manifest.toml + Dockerfile.agents)

| Source | Volume Target | Container Link | Flags | Notes |
|--------|---------------|----------------|-------|-------|
| .bash_aliases | shell/bash_aliases | ~/.bash_aliases_imported | fR | Different name in container |
| .bashrc.d/ | shell/bashrc.d | (none - sourced from volume) | dp | p excludes *.priv.* |
| .zshrc | shell/zshrc | ~/.zshrc | f | |
| .zprofile | shell/zprofile | ~/.zprofile | f | |
| .zshenv | shell/zshenv | ~/.zshenv | f | |
| .inputrc | shell/inputrc | ~/.inputrc | f | |
| .oh-my-zsh/custom | shell/ohmyzsh-custom | ~/.oh-my-zsh/custom | dR | |

### .bashrc.d Sourcing Test (INTERACTIVE SHELL)
```bash
test_bashrc_d_sourced() {
    # Create test script in fixture's .bashrc.d
    mkdir -p "$FIXTURE_HOME/.bashrc.d"
    echo 'export BASHRC_D_TEST="sourced_from_volume"' > "$FIXTURE_HOME/.bashrc.d/test-env.sh"

    run_import --from "$FIXTURE_HOME"

    # Use bash -i -c (interactive) not bash -l -c
    # Scripts are sourced from /mnt/agent-data/shell/bashrc.d
    result=$(exec_in_container bash -i -c 'echo $BASHRC_D_TEST')
    assert_equals "$result" "sourced_from_volume"

    # Verify the file is in the volume path (not ~/.bashrc.d)
    assert_file_exists_in_volume "shell/bashrc.d/test-env.sh"
}
```

### .bashrc.d Priv Filter Test (p flag)
```bash
test_bashrc_d_priv_filter() {
    mkdir -p "$FIXTURE_HOME/.bashrc.d"
    echo 'export PUBLIC_VAR="public"' > "$FIXTURE_HOME/.bashrc.d/public.sh"
    echo 'export SECRET_VAR="secret"' > "$FIXTURE_HOME/.bashrc.d/secrets.priv.sh"

    run_import --from "$FIXTURE_HOME"

    # public.sh should sync
    assert_file_exists_in_volume "shell/bashrc.d/public.sh"
    # secrets.priv.sh should be excluded (p flag)
    assert_file_not_exists_in_volume "shell/bashrc.d/secrets.priv.sh"
}
```

### .bash_aliases Test (linked as ~/.bash_aliases_imported)
```bash
test_aliases_linked_correctly() {
    echo 'alias testcmd="echo works"' > "$FIXTURE_HOME/.bash_aliases"

    run_import --from "$FIXTURE_HOME"

    # File syncs to shell/bash_aliases
    assert_file_exists_in_volume "shell/bash_aliases"

    # Container has it linked as ~/.bash_aliases_imported
    assert_symlink_target "/home/agent/.bash_aliases_imported" "/mnt/agent-data/shell/bash_aliases"

    # Alias should work in interactive shell
    result=$(exec_in_container bash -i -c 'testcmd')
    assert_equals "$result" "works"
}
```

### .inputrc Test
```bash
test_inputrc_synced() {
    echo '"\e[A": history-search-backward' > "$FIXTURE_HOME/.inputrc"

    run_import --from "$FIXTURE_HOME"

    # Verify file synced and readable
    assert_file_exists_in_volume "shell/inputrc"
    assert_symlink_target "/home/agent/.inputrc" "/mnt/agent-data/shell/inputrc"
}
```

### oh-my-zsh/custom Test (R flag)
```bash
test_ohmyzsh_custom_with_R_flag() {
    mkdir -p "$FIXTURE_HOME/.oh-my-zsh/custom/themes"
    echo "ZSH_THEME=custom" > "$FIXTURE_HOME/.oh-my-zsh/custom/themes/custom.zsh-theme"

    run_import --from "$FIXTURE_HOME"

    # Verify synced with R flag (remove existing first)
    assert_file_exists_in_volume "shell/ohmyzsh-custom/themes/custom.zsh-theme"
}
```

## Key context

- Use `bash -i -c` for interactive shell (sources .bashrc hooks)
- .bashrc.d scripts sourced from /mnt/agent-data/shell/bashrc.d NOT ~/.bashrc.d
- Aliases linked as ~/.bash_aliases_imported (different from source name)
- p flag excludes *.priv.* files in .bashrc.d (security)
- zsh tests only if zsh is installed in container

## Acceptance
- [ ] .bashrc.d sourced via bash -i -c (correct path)
- [ ] .bashrc.d *.priv.* files excluded (p flag)
- [ ] .bash_aliases linked as ~/.bash_aliases_imported
- [ ] Alias works in interactive container shell
- [ ] .inputrc synced correctly
- [ ] .zshrc synced correctly
- [ ] .zprofile synced correctly
- [ ] .oh-my-zsh/custom synced with R flag

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
