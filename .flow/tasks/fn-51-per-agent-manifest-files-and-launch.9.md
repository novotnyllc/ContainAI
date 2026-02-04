# Task fn-51.9: Add tests for per-agent manifests and update directory pollution tests

**Status:** pending
**Depends on:** fn-51.5, fn-51.6, fn-51.7

## Objective

Add comprehensive tests for the new per-agent manifest system and update existing tests.

## Test Categories

### 1. Unit Tests: Manifest Parsing

Location: `tests/unit/` (new)

```bash
# Test parse-manifest.sh with directory input
test_parse_manifest_directory() {
    # Setup: create temp manifests dir with test files
    # Assert: output matches expected entries
}

# Test [agent] section parsing
test_parse_agent_section() {
    # Assert: name, binary, default_args, aliases, optional extracted correctly
}

# Test invalid TOML handling
test_invalid_toml_fails() {
    # Assert: malformed TOML produces error, doesn't silently skip
}
```

### 2. Generator Tests

Location: `tests/integration/`

```bash
# Test generators produce equivalent output
test_generators_equivalent_output() {
    # Generate from old sync-manifest.toml (if kept for comparison)
    # Generate from new src/manifests/
    # Assert: outputs are equivalent (modulo ordering/comments)
}

# Test launch wrapper generation
test_launch_wrappers_generated() {
    # Assert: all agents with [agent] section produce wrappers
    # Assert: default_args included in wrapper
    # Assert: optional agents have command -v guard
    # Assert: aliases (e.g., kimi-cli) also generate wrappers
}
```

### 3. Integration Tests: Directory Pollution

Location: `tests/integration/test-sync-integration.sh` (update existing)

```bash
# Existing test - update to use new structure
test_optional_agents_no_empty_dirs() {
    # Fresh container without optional agent configs on host
    # Assert: no ~/.gemini, ~/.copilot, ~/.pi, ~/.kimi dirs created
}

# Test optional flag respected
test_optional_flag_skips_missing() {
    # Host missing ~/.gemini/
    # Assert: import succeeds, no gemini entries synced
}
```

### 4. Integration Tests: User Manifests

Location: `tests/integration/test-user-manifests.sh` (new)

```bash
# Test user manifest synced and processed
test_user_manifest_processed() {
    # Create user manifest on host
    # cai run --fresh
    # Assert: symlinks created in container
    # Assert: wrapper function available
}

# Test invalid user manifest doesn't break startup
test_invalid_user_manifest_logged() {
    # Create malformed user manifest
    # cai run --fresh
    # Assert: container starts successfully
    # Assert: error logged
}

# Test user manifest with optional binary
test_user_manifest_optional_binary() {
    # User manifest with optional=true, binary not installed
    # Assert: no wrapper created (no error)
}
```

### 5. E2E Tests: Launch Wrappers Work

Location: `tests/integration/test-launch-wrappers.sh` (new)

**Critical: Test plain `ssh container 'cmd'` without extra shell wrapper**

```bash
# Test wrapper works in non-interactive SSH (plain command)
# THIS IS THE CRITICAL TEST - ssh without bash -c wrapper
test_wrapper_plain_noninteractive_ssh() {
    # ssh container 'claude --version'   # <-- plain, no bash -c
    # Assert: wrapper still invoked, default args applied
}

# Test wrapper works in non-interactive SSH (with bash -c)
test_wrapper_bash_c_noninteractive_ssh() {
    # ssh container bash -c 'claude --version'
    # Assert: wrapper still invoked
}

# Test wrapper works in interactive shell
test_wrapper_interactive() {
    # ssh container (interactive) then run claude --version
    # Assert: wrapper invoked
}

# Test wrapper prepends default args
test_wrapper_prepends_args() {
    # ssh container 'type claude'
    # Assert: shows function definition with --dangerously-skip-permissions
}

# Test kimi aliases work
test_kimi_aliases() {
    # ssh container 'type kimi'
    # ssh container 'type kimi-cli'
    # Assert: both are functions with --yolo
}
```

## Existing Tests to Update

1. `tests/integration/test-sync-integration.sh`
   - Update paths from `sync-manifest.toml` to `src/manifests/`
   - Add directory pollution assertions for optional agents

2. `tests/integration/test-sync-e2e.sh`
   - Verify still passes with new structure

3. `scripts/check-manifest-consistency.sh`
   - Already updated in Task 7, verify tests pass

## Acceptance Criteria

- [ ] Unit tests for manifest parsing added
- [ ] Generator equivalence tests added
- [ ] Directory pollution tests updated
- [ ] User manifest integration tests added
- [ ] Launch wrapper E2E tests added
- [ ] **Plain `ssh container 'cmd'` test included** (not just `bash -c` variant)
- [ ] All existing tests still pass
- [ ] CI runs new tests

## Notes

- Use existing test patterns from `tests/integration/`
- Tests should be hermetic (no dependency on host config)
- Clean up test containers/volumes after each test
- **Critical:** Include plain `ssh container 'cmd'` test - this tests the BASH_ENV path

## Done summary
Added comprehensive tests for the per-agent manifest system: unit tests for manifest parsing (parse-manifest.sh, gen-agent-wrappers.sh, gen-import-map.sh, parse-toml.py), integration tests for launch wrappers and user manifests, and Sysbox runtime tests including real SSH verification, invalid manifest handling, and optional binary behavior.
## Evidence
- Commits: 230d36d03fe892269f5a6d58d7c174877ae97263, 8430003, ad4235a, 6e090af, b68e65c, 1b3e92a, 3582f06, 1203403
- Tests: ./tests/unit/test-manifest-parsing.sh, ./scripts/check-manifest-consistency.sh
- PRs:
