# fn-12-css.13 Add integration tests for workspace-centric features

## Description

Create comprehensive integration tests for all the new workspace-centric features. These tests ensure the UX improvements work correctly end-to-end.

**Test file:** `tests/integration/test-workspace-ux.sh`

**Test scenarios:**

### 1. Workspace State Persistence
```bash
test_workspace_state_persistence() {
    # First invocation should auto-generate and save volume
    cai shell --dry-run  # Check generated volume name

    # Second invocation should use saved volume
    cai shell --dry-run  # Should show same volume, no generation

    # Verify config file has workspace section
    grep -q "workspace.\"$PWD\"" ~/.config/containai/config.toml
}
```

### 2. One-Shot Exec
```bash
test_exec_command() {
    # Basic command execution
    output=$(cai exec echo hello)
    assert_equals "hello" "$output"

    # Exit code propagation
    cai exec false && fail "Should have failed"

    # Args with spaces
    output=$(cai exec echo "hello world")
    assert_equals "hello world" "$output"

    # No-prompt mode
    cai exec --no-prompt true  # Should not prompt
}
```

### 3. Config Command
```bash
test_config_command() {
    # Set and get
    cai config set ssh.forward_agent true
    value=$(cai config get ssh.forward_agent)
    assert_equals "true" "$value"

    # Unset
    cai config unset ssh.forward_agent
    cai config get ssh.forward_agent && fail "Should not exist"

    # List
    cai config list | grep -q "ssh.forward_agent"

    # Workspace config
    cai config set --workspace data_volume myvolume
    grep -q "workspace.\"$PWD\"" ~/.config/containai/config.toml
}
```

### 4. .env Hierarchy
```bash
test_env_hierarchy() {
    # Create hierarchy
    echo "GLOBAL_VAR=global" > ~/.config/containai/default.env
    mkdir -p ~/.config/containai/volumes
    echo "VOLUME_VAR=volume" > ~/.config/containai/volumes/test-vol.env
    mkdir -p .containai
    echo "WORKSPACE_VAR=workspace" > .containai/env

    # Override test
    echo "SHARED_VAR=global" >> ~/.config/containai/default.env
    echo "SHARED_VAR=workspace" >> .containai/env

    # Import and verify
    cai import --dry-run | grep "SHARED_VAR=workspace"
}
```

### 5. .priv. Exclusion
```bash
test_priv_exclusion() {
    # Create test files
    mkdir -p ~/.bashrc.d
    echo "export NORMAL=1" > ~/.bashrc.d/01_normal.sh
    echo "export SECRET=password" > ~/.bashrc.d/02_secrets.priv.sh

    # Import and verify
    cai import --dry-run | grep -v "secrets.priv.sh"
}
```

### 6. Import Prompting
```bash
test_import_prompt() {
    # Non-interactive should not prompt
    echo "" | cai shell --dry-run  # Should not hang

    # Config disable
    cai config set import.auto_prompt false
    cai shell --dry-run  # Should not prompt
}
```

## Acceptance

- [ ] All test scenarios pass
- [ ] Tests run in CI (Docker required)
- [ ] Tests are hermetic (temp HOME, cleanup)
- [ ] Dry-run tests don't require real containers

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
