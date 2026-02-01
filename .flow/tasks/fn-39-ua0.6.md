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

<!-- Updated by plan-sync: fn-39-ua0.2 used run_cai_import_from, $SYNC_TEST_FIXTURE_HOME, and || return 1 pattern -->

### No Pollution Test (Optional Entries)
```bash
test_no_pollution_optional_agents() {
    # Create only Claude config (non-optional agent)
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    echo '{}' > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"

    # DON'T create Pi, Kimi, Cursor configs (optional agents)

    run_cai_import_from

    # Claude should exist
    assert_path_exists_in_container "/home/agent/.claude" || return 1

    # Optional agents should NOT exist (no symlinks, no dirs)
    assert_path_not_exists_in_container "/home/agent/.pi" || return 1
    assert_path_not_exists_in_container "/home/agent/.kimi" || return 1
    assert_path_not_exists_in_container "/home/agent/.cursor" || return 1

    # No volume entries either
    assert_path_not_exists_in_volume "pi" || return 1
    assert_path_not_exists_in_volume "kimi" || return 1
    assert_path_not_exists_in_volume "cursor" || return 1
}
```

### Partial Config Test (Non-Optional - Placeholder Behavior)
```bash
test_partial_config_non_optional() {
    # Create .claude dir but only settings.json
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    echo '{"editor": "vim"}' > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"
    # Don't create .credentials.json (fs - secret, non-optional)

    run_cai_import_from

    # settings.json should sync with content
    assert_file_exists_in_volume "claude/settings.json" || return 1
    content=$(cat_from_volume "claude/settings.json")
    [[ "$content" == *"editor"* ]] || return 1

    # .credentials.json: missing source with s/j/d flags gets placeholder
    # In import.sh, ensure() is called for missing s/j/d sources
    # Placeholder exists with 600 perms but empty
    assert_file_exists_in_volume "claude/credentials.json" || return 1
    assert_permissions_in_volume "claude/credentials.json" "600" || return 1
}
```

### Partial Config Test (Optional Agent)
```bash
test_partial_config_optional_agent() {
    # Create partial Pi config
    # Source: .pi/agent/settings.json -> Target: pi/settings.json
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.pi/agent"
    echo '{}' > "$SYNC_TEST_FIXTURE_HOME/.pi/agent/settings.json"
    # Don't create models.json, keybindings.json

    run_cai_import_from

    # settings.json syncs (source exists)
    # Note: target is "pi/settings.json" not "pi/agent/settings.json"
    assert_file_exists_in_volume "pi/settings.json" || return 1

    # models.json NOT created (fjso - optional, source missing)
    # Target would be "pi/models.json"
    assert_path_not_exists_in_volume "pi/models.json" || return 1

    # keybindings.json NOT created (fjo - optional, source missing)
    assert_path_not_exists_in_volume "pi/keybindings.json" || return 1
}
```

### Large Directory Test
```bash
test_large_fonts_directory() {
    # Create fonts/ with multiple files
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.local/share/fonts"
    for i in $(seq 1 50); do
        # Create small dummy font files
        echo "font$i" > "$SYNC_TEST_FIXTURE_HOME/.local/share/fonts/font$i.ttf"
    done

    run_cai_import_from

    # Verify all fonts synced
    count=$(exec_in_container "$SYNC_TEST_CONTAINER" find /mnt/agent-data/local/share/fonts -type f -name '*.ttf' | wc -l)
    [[ "$count" -eq 50 ]] || return 1
}
```

### Unicode Content Test
```bash
test_unicode_content_preserved() {
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    echo '{"name": "Test User", "emoji": "rocket", "chinese": "nihao"}' > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"

    run_cai_import_from

    content=$(cat_from_volume "claude/settings.json")
    [[ "$content" == *"rocket"* ]] || return 1
    [[ "$content" == *"nihao"* ]] || return 1
}
```

### Symlink Relinking Test
```bash
test_internal_symlink_relinked() {
    # Create directory with internal absolute symlink
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.agents/shared"
    echo 'shared config' > "$SYNC_TEST_FIXTURE_HOME/.agents/shared/base.yml"
    # Create absolute symlink pointing to host path
    ln -s "$SYNC_TEST_FIXTURE_HOME/.agents/shared/base.yml" "$SYNC_TEST_FIXTURE_HOME/.agents/link.yml"

    run_cai_import_from

    # Symlink should be relinked to container path
    # (Not original host path which wouldn't exist in container)
    link_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink /home/agent/.agents/link.yml)
    [[ "$link_target" != *"$SYNC_TEST_FIXTURE_HOME"* ]] || return 1
}
```

### Concurrent Containers (Separate Volumes)
```bash
# Note: This test requires manual container/volume management since the test
# harness uses a single container per test. Use run_agent_sync_test pattern
# and modify for multi-container scenario.

test_concurrent_containers_separate_volumes() {
    # Each container uses its own volume to avoid conflicts
    # This is the expected production pattern

    # Create two volumes
    local vol1 vol2
    vol1=$(create_test_volume "concurrent-vol1")
    vol2=$(create_test_volume "concurrent-vol2")

    # Create two containers with separate volumes
    create_test_container "concurrent-1" \
        --volume "$vol1:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null
    create_test_container "concurrent-2" \
        --volume "$vol2:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

    local container1="test-concurrent-1-${SYNC_TEST_RUN_ID}"
    local container2="test-concurrent-2-${SYNC_TEST_RUN_ID}"

    # Create fixture
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    echo '{}' > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"

    # Import to both containers (via their volumes)
    HOME="$SYNC_TEST_PROFILE_HOME" bash -c 'source "$1/containai.sh" && shift && cai import "$@"' _ "$SYNC_TEST_SRC_DIR" --from "$SYNC_TEST_FIXTURE_HOME" --data-volume "$vol1" 2>&1
    HOME="$SYNC_TEST_PROFILE_HOME" bash -c 'source "$1/containai.sh" && shift && cai import "$@"' _ "$SYNC_TEST_SRC_DIR" --from "$SYNC_TEST_FIXTURE_HOME" --data-volume "$vol2" 2>&1

    # Start containers
    start_test_container "$container1"
    start_test_container "$container2"

    # Both should have configs independently
    "${DOCKER_CMD[@]}" exec "$container1" test -f /home/agent/.claude/settings.json || return 1
    "${DOCKER_CMD[@]}" exec "$container2" test -f /home/agent/.claude/settings.json || return 1

    # Modify one, verify other unchanged
    "${DOCKER_CMD[@]}" exec "$container1" bash -c 'echo "modified" >> /mnt/agent-data/claude/settings.json'
    content2=$("${DOCKER_CMD[@]}" exec "$container2" cat /mnt/agent-data/claude/settings.json)
    [[ "$content2" != *"modified"* ]] || return 1

    # Cleanup handled by trap
}
```

## Key context

- "No pollution" specifically for optional (o flag) entries
- Missing non-optional s/j/d entries: placeholder created (ensure() called)
- Missing optional entries: completely skipped (no target)
- Pi paths: source `.pi/agent/x` -> target `pi/x` (no `agent` in target)
- Symlink relinking handled by import.sh for internal absolute symlinks
- Concurrent containers use separate volumes (production pattern)
- Test infrastructure: use `$SYNC_TEST_FIXTURE_HOME`, `$SYNC_TEST_CONTAINER`, `run_cai_import_from`
- Pattern matching: use `[[ "$var" == *"pattern"* ]] || return 1` instead of `assert_contains`
- Multi-container: create volumes/containers manually using `create_test_volume`/`create_test_container`

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
