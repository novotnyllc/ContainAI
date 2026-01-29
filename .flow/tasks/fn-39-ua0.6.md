# fn-39-ua0.6 Edge case tests

## Description
Test edge cases: no-config pollution, partial configs, large directories, special characters.

**Size:** M
**Files:** `tests/integration/sync-tests/test-edge-cases.sh`

## Approach

### Edge Cases to Test

| Case | Test |
|------|------|
| No config on host | Verify no empty dirs created in container |
| Partial config | Some files exist, others don't - handled gracefully |
| Large directory | fonts/ with many files syncs correctly |
| Spaces in filename | "My Config.json" syncs correctly |
| Unicode in content | Config with emoji/unicode preserved |
| Broken symlink | Graceful handling, no crash |
| Permission mismatch | Files with unusual permissions |
| Concurrent containers | Two containers don't conflict |

### Test Structure
```bash
test_no_config_no_pollution() {
    # Don't create any Pi config
    run_import
    # Verify no .pi directory exists
    assert_dir_not_exists_in_container "~/.pi"
}

test_partial_config() {
    # Create only settings.json, not models.json
    echo '{}' > "$TEST_HOME/.pi/agent/settings.json"
    run_import
    assert_file_exists_in_container "~/.pi/agent/settings.json"
    # models.json should be json-init'd to {}
    assert_file_exists_in_container "~/.pi/agent/models.json"
}

test_spaces_in_filename() {
    mkdir -p "$TEST_HOME/.config/test"
    echo 'test' > "$TEST_HOME/.config/test/My Config.json"
    run_import
    assert_file_exists_in_container "~/.config/test/My Config.json"
}

test_unicode_content() {
    echo '{"emoji": "🚀", "chinese": "你好"}' > "$TEST_HOME/.claude/settings.json"
    run_import
    content=$(exec_in_container cat ~/.claude/settings.json)
    assert_contains "$content" "🚀"
}

test_concurrent_containers() {
    start_test_container "test-sync-1"
    start_test_container "test-sync-2"
    run_import_to "test-sync-1"
    run_import_to "test-sync-2"
    # Both should have configs, no conflicts
    assert_file_exists_in_container "test-sync-1" "~/.claude/settings.json"
    assert_file_exists_in_container "test-sync-2" "~/.claude/settings.json"
}
```

## Key context

- "No pollution" = empty directories shouldn't be created for agents user doesn't have
- Partial config tests json-init flag behavior
- Concurrent container test ensures no locking issues
## Acceptance
- [ ] No-config = no empty directories created
- [ ] Partial config handled (missing files json-init'd)
- [ ] Large directory (fonts/) syncs correctly
- [ ] Spaces in filenames handled
- [ ] Unicode in content preserved
- [ ] Broken symlinks handled gracefully
- [ ] Concurrent containers don't conflict
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
