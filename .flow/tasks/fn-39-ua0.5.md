# fn-39-ua0.5 Flag and operation tests

## Description
Test all sync flags and operations: s, j, R, x flags, --no-secrets, import, export, dry-run.

**Size:** M
**Files:** `tests/integration/sync-tests/test-flags.sh`

## Approach

### Flag Tests

| Flag | Test Case |
|------|-----------|
| `s` (secret) | File gets 600 permissions |
| `j` (json-init) | Missing file → creates `{}` |
| `R` (remove) | Directory cleaned before sync |
| `x` (exclude) | .system/ subdirectory skipped |

### Operation Tests

| Operation | Test Case |
|-----------|-----------|
| `cai import` | Host → container sync |
| `cai export` | Container → host sync |
| `cai import --dry-run` | Shows changes, no actual sync |
| `cai export --dry-run` | Shows changes, no actual sync |
| `cai import --no-secrets` | Skips files with `s` flag |

### Test Structure
```bash
test_secret_flag() {
    echo '{"key": "secret"}' > "$TEST_HOME/.claude/.credentials.json"
    run_import
    perms=$(exec_in_container stat -c '%a' ~/.claude/.credentials.json)
    assert_equals "$perms" "600"
}

test_json_init_flag() {
    # Don't create the file - let json-init create it
    run_import
    content=$(exec_in_container cat ~/.claude/settings.json)
    assert_equals "$content" "{}"
}

test_no_secrets_option() {
    echo '{"key": "secret"}' > "$TEST_HOME/.claude/.credentials.json"
    run_import --no-secrets
    # File should NOT exist in container
    assert_file_not_exists_in_container "~/.claude/.credentials.json"
}

test_dry_run() {
    output=$(run_import --dry-run)
    assert_contains "$output" "would sync"
    # Verify no actual changes
    assert_file_not_exists_in_container "~/.claude/settings.json"
}
```

## Key context

- `j` flag creates empty `{}` for JSON files that don't exist on host
- `R` flag removes existing directory contents before syncing
- `x` flag is used for entries like plugins/ that have .system/ subdirs
## Acceptance
- [ ] Secret flag (s) - 600 permissions verified
- [ ] JSON-init flag (j) - creates empty {} for missing files
- [ ] Remove flag (R) - cleans directory before sync
- [ ] Exclude flag (x) - skips .system/ subdirectories
- [ ] cai import works (host → container)
- [ ] cai export works (container → host)
- [ ] --dry-run shows changes without syncing
- [ ] --no-secrets excludes secret files
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
