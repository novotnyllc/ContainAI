# fn-39-ua0.2 AI agent sync tests

## Description
Test sync for all 10 AI agents: Claude, Gemini, Codex, Copilot, OpenCode, Aider, Continue, Cursor, Pi, Kimi.

**Size:** M
**Files:** `tests/integration/sync-tests/test-agent-sync.sh`

## Approach

For each agent, test:
1. Config files sync from mock HOME to container
2. Secret files have correct permissions (600)
3. Directories sync recursively
4. Symlinks point to /mnt/agent-data/
5. Agent CLI works after sync (--version or equivalent)

### Agents to Test

| Agent | Test Files | Secret Files |
|-------|------------|--------------|
| Claude | settings.json, plugins/ | .credentials.json |
| Gemini | settings.json, GEMINI.md | google_accounts.json, oauth_creds.json |
| Codex | config.toml, skills/ | auth.json |
| Copilot | config.json, skills/ | mcp-config.json |
| OpenCode | opencode.json, agents/ | auth.json |
| Aider | .aider.conf.yml | .aider.model.settings.yml |
| Continue | config.yaml | config.json |
| Cursor | rules/, extensions/ | mcp.json |
| Pi | settings.json, skills/ | models.json |
| Kimi | mcp.json | config.toml |

### Test Structure
```bash
test_claude_sync() {
    create_mock_claude_config
    run_import
    assert_file_exists_in_container "~/.claude/settings.json"
    assert_symlink_target "~/.claude/settings.json" "/mnt/agent-data/claude/settings.json"
    assert_permissions "~/.claude/.credentials.json" "600"
    exec_in_container claude --version
}
```

## Key context

- Some agents may not be installed - skip gracefully with info message
- Use patterns from sync-manifest.toml for correct paths
## Acceptance
- [ ] Claude Code sync tested
- [ ] Gemini sync tested
- [ ] Codex sync tested
- [ ] Copilot sync tested
- [ ] OpenCode sync tested
- [ ] Aider sync tested
- [ ] Continue sync tested
- [ ] Cursor sync tested
- [ ] Pi sync tested
- [ ] Kimi sync tested
- [ ] All secret files have 600 permissions
- [ ] All symlinks resolve correctly
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
