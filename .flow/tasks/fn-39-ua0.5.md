# fn-39-ua0.5 Flag and operation tests

## Description
Test manifest flag behaviors and CLI operations: s, j, R, x, o flags, --no-secrets, --dry-run, import AND export operations.

**Size:** M
**Files:** `tests/integration/sync-tests/test-flags.sh`

## Approach

### Manifest Flag Tests

| Flag | Behavior | Test Strategy |
|------|----------|---------------|
| `s` | 600 file permissions | Verify permissions after sync |
| `j` | Creates {} for empty/missing (non-optional only) | Test with non-optional fj entry |
| `R` | rm -rf existing path before symlink creation | Create conflicting dir, verify symlink replacement |
| `x` | Excludes .system/ subdirectory | Create .system/ in source, verify not synced |
| `p` | Excludes *.priv.* files | Tested in fn-39-ua0.4 |
| `g` | Strips credential.helper/signing from gitconfig | Tested in fn-39-ua0.3 |
| `o` | Optional - missing source = no target created | Verify no target for missing optional entries |

Note: No directory entries have `s` flag in sync-manifest.toml, so 700 directory permissions are not tested here.

<!-- Updated by plan-sync: fn-39-ua0.2 used run_cai_import_from, $SYNC_TEST_FIXTURE_HOME, and || return 1 pattern -->

### s Flag (Secret File Permissions)
```bash
test_secret_file_permissions() {
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    echo '{"token": "secret"}' > "$SYNC_TEST_FIXTURE_HOME/.claude/.credentials.json"
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.codex"
    echo '{"auth": "token"}' > "$SYNC_TEST_FIXTURE_HOME/.codex/auth.json"

    run_cai_import_from

    # Secret files should have 600 permissions
    assert_permissions_in_volume "claude/credentials.json" "600" || return 1
    assert_permissions_in_volume "codex/auth.json" "600" || return 1
}
```

### j Flag (JSON Init - Non-Optional Only)
```bash
test_json_init_non_optional() {
    # .claude/settings.json is fj (non-optional)
    # Create .claude dir but not the file
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"

    run_cai_import_from

    # Should be created with {} because fj (not optional)
    content=$(cat_from_volume "claude/settings.json")
    [[ "$content" == "{}" ]] || return 1
}

test_json_init_optional_skipped() {
    # .gemini/settings.json is fjo (optional)
    # Don't create any .gemini files

    run_cai_import_from

    # Should NOT be created (optional entry, source missing)
    assert_path_not_exists_in_volume "gemini/settings.json" || return 1
}
```

### R Flag (Remove Existing Before Symlink)
```bash
test_R_flag_symlink_replacement() {
    # R flag removes existing path before creating symlink
    # This prevents nested symlinks when dir exists

    # Create fixture with .claude/plugins content
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude/plugins"
    echo 'plugin' > "$SYNC_TEST_FIXTURE_HOME/.claude/plugins/test.js"

    # First import creates the structure
    run_cai_import_from

    # Now create a conflicting directory at the symlink location
    exec_in_container "$SYNC_TEST_CONTAINER" rm -rf /home/agent/.claude/plugins
    exec_in_container "$SYNC_TEST_CONTAINER" mkdir -p /home/agent/.claude/plugins
    exec_in_container "$SYNC_TEST_CONTAINER" touch /home/agent/.claude/plugins/conflict.txt

    # Re-run container setup (which creates symlinks with R flag)
    # Stop and start container to re-run entrypoint symlink creation
    stop_test_container "$SYNC_TEST_CONTAINER"
    start_test_container "$SYNC_TEST_CONTAINER"

    # Symlink should replace the directory (not nest inside)
    link_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink /home/agent/.claude/plugins)
    [[ "$link_target" == "/mnt/agent-data/claude/plugins" ]] || return 1
}
```

### x Flag (Exclude .system/)
```bash
test_x_flag_excludes_system() {
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.codex/skills"
    echo 'skill' > "$SYNC_TEST_FIXTURE_HOME/.codex/skills/test.md"
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.codex/skills/.system"
    echo 'system' > "$SYNC_TEST_FIXTURE_HOME/.codex/skills/.system/cache.json"

    run_cai_import_from

    # User skill should sync
    assert_file_exists_in_volume "codex/skills/test.md" || return 1
    # .system/ should be excluded
    assert_path_not_exists_in_volume "codex/skills/.system" || return 1
}
```

### o Flag (Optional - No Target If Missing)
```bash
test_optional_missing_no_target() {
    # Don't create any Pi config (all entries are optional)

    run_cai_import_from

    # No Pi directory should exist
    assert_path_not_exists_in_container "/home/agent/.pi" || return 1
    assert_path_not_exists_in_volume "pi" || return 1
}
```

### CLI Operation Tests - Import

```bash
test_import_dry_run_no_changes() {
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    echo '{"test": true}' > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"

    output=$(run_cai_import_from --dry-run)

    # Should show [DRY-RUN] markers
    [[ "$output" == *"[DRY-RUN]"* ]] || return 1

    # Volume should remain unchanged
    assert_path_not_exists_in_volume "claude/settings.json" || return 1
}

test_import_no_secrets_skips_s_entries() {
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    echo '{"token": "secret"}' > "$SYNC_TEST_FIXTURE_HOME/.claude/.credentials.json"
    echo '{}' > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"

    run_cai_import_from --no-secrets

    # Non-secret file should sync
    assert_file_exists_in_volume "claude/settings.json" || return 1
    # Secret file should be skipped entirely
    assert_path_not_exists_in_volume "claude/credentials.json" || return 1
}
```

### CLI Operation Tests - Export

Note: `cai export` creates a `.tgz` archive file. The CLI uses `-o/--output` flag.
Note: Export does NOT support `--dry-run` (not implemented in CLI).
Note: Export helper `run_cai_export` needs to be added to sync-test-helpers.sh.

```bash
# Helper for export (add to sync-test-helpers.sh)
run_cai_export() {
    HOME="$SYNC_TEST_PROFILE_HOME" bash -c 'source "$1/containai.sh" && shift && cai export "$@"' _ "$SYNC_TEST_SRC_DIR" --data-volume "$SYNC_TEST_DATA_VOLUME" "$@" 2>&1
}

test_export_basic() {
    # First import some data
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    echo '{"original": true}' > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"
    run_cai_import_from

    # Modify data in container volume
    exec_in_container "$SYNC_TEST_CONTAINER" bash -c 'echo "{\"modified\": true}" > /mnt/agent-data/claude/settings.json'

    # Export to a .tgz archive
    EXPORT_ARCHIVE=$(mktemp --suffix=.tgz)
    run_cai_export --output "$EXPORT_ARCHIVE"

    # Verify archive contains expected files
    tar -tzf "$EXPORT_ARCHIVE" | grep -q "claude/settings.json" || return 1

    # Extract and verify content
    EXTRACT_DIR=$(mktemp -d)
    tar -xzf "$EXPORT_ARCHIVE" -C "$EXTRACT_DIR"
    content=$(cat "$EXTRACT_DIR/claude/settings.json")
    [[ "$content" == *"modified"* ]] || return 1
}

test_export_with_config_excludes() {
    # Export excludes come from top-level default_excludes in config
    # Create config with exclude patterns (top-level, not [export] section)
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai"
    cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/containai.toml" <<'EOF'
default_excludes = ["shell/bashrc.d/*.priv.*"]
EOF

    # Import some data
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.bashrc.d"
    echo 'public' > "$SYNC_TEST_FIXTURE_HOME/.bashrc.d/public.sh"
    run_cai_import_from

    # Add a .priv file directly to volume (simulating container-side creation)
    exec_in_container "$SYNC_TEST_CONTAINER" bash -c 'echo "secret" > /mnt/agent-data/shell/bashrc.d/secret.priv.sh'

    # Export with config that has excludes
    EXPORT_ARCHIVE=$(mktemp --suffix=.tgz)
    run_cai_export --output "$EXPORT_ARCHIVE" --config "$SYNC_TEST_FIXTURE_HOME/.config/containai/containai.toml"

    # Extract archive
    EXTRACT_DIR=$(mktemp -d)
    tar -xzf "$EXPORT_ARCHIVE" -C "$EXTRACT_DIR"

    # public.sh should be in archive
    [[ -f "$EXTRACT_DIR/shell/bashrc.d/public.sh" ]] || return 1
    # .priv file should be excluded per config
    [[ ! -e "$EXTRACT_DIR/shell/bashrc.d/secret.priv.sh" ]] || return 1
}

test_export_no_excludes_flag() {
    # --no-excludes skips exclude patterns
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai"
    cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/containai.toml" <<'EOF'
default_excludes = ["claude/*"]
EOF

    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    echo '{}' > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"
    run_cai_import_from

    # Export with --no-excludes
    EXPORT_ARCHIVE=$(mktemp --suffix=.tgz)
    run_cai_export --output "$EXPORT_ARCHIVE" --config "$SYNC_TEST_FIXTURE_HOME/.config/containai/containai.toml" --no-excludes

    # claude/settings.json should be in archive (excludes skipped)
    tar -tzf "$EXPORT_ARCHIVE" | grep -q "claude/settings.json" || return 1
}
```

## Key context

- `j` only creates {} for non-optional entries
- `R` is for symlink creation, not rsync directory cleaning
- `o` entries are completely skipped when source missing
- No `ds` entries exist, so 700 dir permissions not testable
- --dry-run shows [DRY-RUN] markers for import
- --no-secrets skips s-flagged entries entirely (no placeholder)
- Export creates `.tgz` archive with `-o/--output` flag
- Export does NOT support `--dry-run`
- Export excludes come from top-level `default_excludes` in config, NOT manifest flags

## Acceptance
- [ ] s flag: 600 file permissions verified
- [ ] j flag: {} created for non-optional fj entries
- [ ] j flag: optional fjo entries NOT created when missing
- [ ] R flag: symlink replaces conflicting directory
- [ ] x flag: .system/ excluded from Codex/Pi skills
- [ ] o flag: missing optional = no target
- [ ] cai import works (host → container)
- [ ] cai import --dry-run: [DRY-RUN] output, no volume changes
- [ ] cai import --no-secrets: s-flagged entries skipped entirely
- [ ] cai export creates .tgz archive
- [ ] cai export with config excludes works
- [ ] cai export --no-excludes skips excludes

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
