# fn-39-ua0.4 Shell customization tests

## Description
Test shell customization sync: .bashrc.d sourcing, aliases, inputrc, zsh configs.

**Size:** M
**Files:** `tests/integration/sync-tests/test-shell-sync.sh`

## Approach

### Critical: .bashrc.d Sourcing

The most important test - verify .bashrc.d scripts are sourced on login:

```bash
test_bashrc_d_sourced() {
    # Create test script in mock .bashrc.d
    echo 'export BASHRC_D_TEST="sourced"' > "$TEST_HOME/.bashrc.d/test.sh"

    run_import

    # Start interactive shell and check variable
    result=$(exec_in_container bash -l -c 'echo $BASHRC_D_TEST')
    assert_equals "$result" "sourced"
}
```

### Items to Test

| Item | Test |
|------|------|
| .bashrc.d/ | Scripts sourced on login shell |
| .bash_aliases | Aliases available after login |
| .inputrc | Readline bindings applied |
| .zshrc | Zsh config loaded |
| .zprofile | Zsh profile loaded |
| .oh-my-zsh/custom | Custom themes/plugins available |

### Test Structure
```bash
test_aliases_available() {
    echo 'alias testcmd="echo works"' > "$TEST_HOME/.bash_aliases"
    run_import
    result=$(exec_in_container bash -l -c 'testcmd')
    assert_equals "$result" "works"
}

test_inputrc_bindings() {
    echo '"\e[A": history-search-backward' > "$TEST_HOME/.inputrc"
    run_import
    assert_file_exists_in_container "~/.inputrc"
    # Note: Actually testing readline bindings is complex
}
```

## Key context

- Use `bash -l` for login shell (sources .bashrc.d)
- .bashrc.d is a directory of scripts, not a single file
- zsh tests only if zsh is installed in container
## Acceptance
- [ ] .bashrc.d/ scripts sourced on login
- [ ] .bash_aliases available after login
- [ ] .inputrc synced correctly
- [ ] .zshrc synced correctly
- [ ] .zprofile synced correctly
- [ ] .oh-my-zsh/custom synced correctly
- [ ] Custom alias works in container shell
- [ ] Custom .bashrc.d script exports variable
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
