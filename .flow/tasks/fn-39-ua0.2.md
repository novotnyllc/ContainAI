# fn-39-ua0.2 AI agent sync tests

## Description
Test sync for all 10 AI agents using `--from <fixture>` to validate full content sync.

**Size:** M
**Files:** `tests/integration/sync-tests/test-agent-sync.sh`

## Approach

Use `--from <mock-home>` for main validation (syncs full content including secrets).
Add separate profile-import tests for placeholder behavior.

### Agents to Test (from sync-manifest.toml)

| Agent | Key Entries | Flags | Notes |
|-------|-------------|-------|-------|
| Claude | .claude.json (fjs), .credentials.json (fs), settings.json (fj), settings.local.json (f), plugins/ (dR), skills/ (dR), commands/ (dR), agents/ (dR), hooks/ (dR), CLAUDE.md (f) | Various | Profile import skips secrets |
| OpenCode | opencode.json (fjs), instructions.md (f), agents/ (d), commands/ (d), skills/ (d), modes/ (d), plugins/ (d), auth.json (fs at ~/.local/share/opencode/) | fjs/fs/d | auth.json at different path |
| Codex | config.toml (f), auth.json (fs), skills (dxR) | f/fs/dxR | x flag excludes .system/ |
| Copilot | config.json (fo), mcp-config.json (fo), skills (dRo) | fo/dRo | All optional - not secret |
| Gemini | google_accounts.json (fso), oauth_creds.json (fso), settings.json (fjo), GEMINI.md (fo) | fso/fjo/fo | All optional |
| Aider | .aider.conf.yml (fso), .aider.model.settings.yml (fso) | fso | Optional secrets |
| Continue | config.yaml (fso), config.json (fjso) | fso/fjso | Optional |
| Cursor | mcp.json (fjso), rules (dRo), extensions (dRo) | fjso/dRo | Optional |
| Pi | settings.json (fjo), models.json (fjso), keybindings.json (fjo), skills (dxRo), extensions (dRo) | fjo/fjso/dxRo | Optional |
| Kimi | config.toml (fso), mcp.json (fjso) | fso/fjso | Optional |

### Test Structure
```bash
test_claude_sync_with_from() {
    # Create fixture with all Claude files
    create_mock_claude_config "$FIXTURE_HOME"

    # Import using --from (full content sync)
    run_import --from "$FIXTURE_HOME"

    # Verify files synced with correct content
    assert_file_exists_in_container "/home/agent/.claude/settings.json"
    assert_symlink_target "/home/agent/.claude/settings.json" "/mnt/agent-data/claude/settings.json"
    assert_file_content_in_volume "claude/settings.json" "$expected_content"

    # Verify secret file permissions
    assert_permissions_in_volume "claude/credentials.json" "600"
}

test_claude_profile_import() {
    # Test profile import behavior (source == HOME)
    # Secrets become placeholders, not copied
    run_import  # No --from = profile import

    # Placeholder should exist with 600 perms but be empty/minimal
    assert_file_exists_in_volume "claude/credentials.json"
    assert_permissions_in_volume "claude/credentials.json" "600"
}

test_optional_agent_missing() {
    # Don't create any Pi config in fixture
    run_import --from "$FIXTURE_HOME"

    # Pi directories should NOT exist (optional entries skipped)
    assert_path_not_exists_in_container "/home/agent/.pi"
}
```

## Key context

- Use `--from <fixture>` for full content validation
- Profile import (no --from) creates placeholders for secrets
- Optional agents (o flag): missing source = no target created
- CLI version checks are optional (may not be installed)

## Acceptance
- [ ] Claude Code sync tested with --from
- [ ] OpenCode sync tested (auth.json at ~/.local/share/opencode/)
- [ ] Codex sync tested (x flag excludes .system/)
- [ ] Copilot sync tested (optional, not secret)
- [ ] Gemini sync tested (optional)
- [ ] Aider sync tested (optional)
- [ ] Continue sync tested (optional)
- [ ] Cursor sync tested (optional)
- [ ] Pi sync tested (optional)
- [ ] Kimi sync tested (optional)
- [ ] Profile-import placeholder behavior tested
- [ ] Optional agent missing = no target created

## Done summary
Added comprehensive content marker assertions to AI agent sync tests, ensuring actual content is verified (not just file existence). All 10 agents have unique markers in fixtures and corresponding verification assertions.
## Evidence
- Commits: ba704409adfb9866cfa3c2634e81bdea8ffcc7cd, 640bd3c1747ddcb3744474da62e9b766a2a17cf2, 153be48, ff9a854, 5ab72c0
- Tests: shellcheck -x tests/integration/sync-*.sh
- PRs:
