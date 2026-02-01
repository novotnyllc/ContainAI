# fn-39-ua0.6 Edge case tests

## Description
Test edge cases: no-pollution for optional entries, partial configs, large directories, symlink relinking, concurrent containers.

**Size:** M
**Files:** `tests/integration/sync-tests/test-edge-cases.sh`

## Approach

### Edge Cases to Test

| Case | Description | Strategy |
|------|-------------|----------|
| No pollution | Optional agent roots not created when missing | Verify no symlink/dir for Pi, Kimi, Cursor when no source |
| Partial config | Some files exist, others don't | Test placeholder behavior |
| Large directory | fonts/ with many files | Verify sync completes correctly |
| Unicode content | Emoji/chinese in config | Verify preserved |
| Symlink relinking | Internal absolute symlinks | Verify remapped correctly |
| Concurrent containers | Two containers with separate volumes | Verify no conflicts |

### No Pollution Test (Optional Entries)
```bash
test_no_pollution_optional_agents() {
    # Create only Claude config (non-optional agent)
    mkdir -p "$FIXTURE_HOME/.claude"
    echo '{}' > "$FIXTURE_HOME/.claude/settings.json"

    # DON'T create Pi, Kimi, Cursor configs (optional agents)

    run_import --from "$FIXTURE_HOME"

    # Claude should exist
    assert_path_exists_in_container "/home/agent/.claude"

    # Optional agents should NOT exist (no symlinks, no dirs)
    assert_path_not_exists_in_container "/home/agent/.pi"
    assert_path_not_exists_in_container "/home/agent/.kimi"
    assert_path_not_exists_in_container "/home/agent/.cursor"

    # No volume entries either
    assert_path_not_exists_in_volume "pi"
    assert_path_not_exists_in_volume "kimi"
    assert_path_not_exists_in_volume "cursor"
}
```

### Partial Config Test (Non-Optional - Placeholder Behavior)
```bash
test_partial_config_non_optional() {
    # Create .claude dir but only settings.json
    mkdir -p "$FIXTURE_HOME/.claude"
    echo '{"editor": "vim"}' > "$FIXTURE_HOME/.claude/settings.json"
    # Don't create .credentials.json (fs - secret, non-optional)

    run_import --from "$FIXTURE_HOME"

    # settings.json should sync with content
    assert_file_exists_in_volume "claude/settings.json"
    content=$(cat_from_volume "claude/settings.json")
    assert_contains "$content" "editor"

    # .credentials.json: missing source with s/j/d flags gets placeholder
    # In import.sh, ensure() is called for missing s/j/d sources
    # Placeholder exists with 600 perms but empty
    assert_file_exists_in_volume "claude/credentials.json"
    assert_permissions_in_volume "claude/credentials.json" "600"
}
```

### Partial Config Test (Optional Agent)
```bash
test_partial_config_optional_agent() {
    # Create partial Pi config
    # Source: .pi/agent/settings.json -> Target: pi/settings.json
    mkdir -p "$FIXTURE_HOME/.pi/agent"
    echo '{}' > "$FIXTURE_HOME/.pi/agent/settings.json"
    # Don't create models.json, keybindings.json

    run_import --from "$FIXTURE_HOME"

    # settings.json syncs (source exists)
    # Note: target is "pi/settings.json" not "pi/agent/settings.json"
    assert_file_exists_in_volume "pi/settings.json"

    # models.json NOT created (fjso - optional, source missing)
    # Target would be "pi/models.json"
    assert_path_not_exists_in_volume "pi/models.json"

    # keybindings.json NOT created (fjo - optional, source missing)
    assert_path_not_exists_in_volume "pi/keybindings.json"
}
```

### Large Directory Test
```bash
test_large_fonts_directory() {
    # Create fonts/ with multiple files
    mkdir -p "$FIXTURE_HOME/.local/share/fonts"
    for i in $(seq 1 50); do
        # Create small dummy font files
        echo "font$i" > "$FIXTURE_HOME/.local/share/fonts/font$i.ttf"
    done

    run_import --from "$FIXTURE_HOME"

    # Verify all fonts synced
    count=$(count_files_in_volume "local/share/fonts")
    assert_equals "$count" "50"
}
```

### Unicode Content Test
```bash
test_unicode_content_preserved() {
    mkdir -p "$FIXTURE_HOME/.claude"
    echo '{"name": "Test User", "emoji": "rocket", "chinese": "nihao"}' > "$FIXTURE_HOME/.claude/settings.json"

    run_import --from "$FIXTURE_HOME"

    content=$(cat_from_volume "claude/settings.json")
    assert_contains "$content" "rocket"
    assert_contains "$content" "nihao"
}
```

### Symlink Relinking Test
```bash
test_internal_symlink_relinked() {
    # Create directory with internal absolute symlink
    mkdir -p "$FIXTURE_HOME/.agents/shared"
    echo 'shared config' > "$FIXTURE_HOME/.agents/shared/base.yml"
    # Create absolute symlink pointing to host path
    ln -s "$FIXTURE_HOME/.agents/shared/base.yml" "$FIXTURE_HOME/.agents/link.yml"

    run_import --from "$FIXTURE_HOME"

    # Symlink should be relinked to container path
    # (Not original host path which wouldn't exist in container)
    link_target=$(exec_in_container "$CONTAINER" readlink /home/agent/.agents/link.yml)
    assert_not_contains "$link_target" "$FIXTURE_HOME"
}
```

### Concurrent Containers (Separate Volumes)
```bash
test_concurrent_containers_separate_volumes() {
    # Each container uses its own volume to avoid conflicts
    # This is the expected production pattern

    CONTAINER1=$(start_test_container "test-sync-1" "vol1")
    CONTAINER2=$(start_test_container "test-sync-2" "vol2")

    # Import to both containers
    run_import_to "$CONTAINER1" --from "$FIXTURE_HOME"
    run_import_to "$CONTAINER2" --from "$FIXTURE_HOME"

    # Both should have configs independently
    assert_file_exists_in_container "$CONTAINER1" "/home/agent/.claude/settings.json"
    assert_file_exists_in_container "$CONTAINER2" "/home/agent/.claude/settings.json"

    # Modify one, verify other unchanged
    exec_in_container "$CONTAINER1" bash -c 'echo "modified" >> /mnt/agent-data/claude/settings.json'
    content2=$(exec_in_container "$CONTAINER2" cat /mnt/agent-data/claude/settings.json)
    assert_not_contains "$content2" "modified"

    cleanup_container "$CONTAINER1"
    cleanup_container "$CONTAINER2"
}
```

## Key context

- "No pollution" specifically for optional (o flag) entries
- Missing non-optional s/j/d entries: placeholder created (ensure() called)
- Missing optional entries: completely skipped (no target)
- Pi paths: source `.pi/agent/x` -> target `pi/x` (no `agent` in target)
- Symlink relinking handled by import.sh for internal absolute symlinks
- Concurrent containers use separate volumes (production pattern)

## Acceptance
- [ ] No-pollution: optional agent roots not created when missing
- [ ] Partial non-optional: placeholder created for missing s/j entries
- [ ] Partial optional: missing files NOT created
- [ ] Pi volume paths correct (pi/settings.json not pi/agent/settings.json)
- [ ] Large directory (fonts/) syncs correctly
- [ ] Unicode content preserved
- [ ] Internal absolute symlinks relinked
- [ ] Concurrent containers with separate volumes work independently

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
