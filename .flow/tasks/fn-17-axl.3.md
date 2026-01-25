# fn-17-axl.3 Selective AI agent folder sync

## Description

Implement selective syncing for AI agent config directories - sync only needed files, skip caches/history/sessions.

**Current state:** Claude and some agents already have selective sync via explicit file entries in `_IMPORT_SYNC_MAP`.

**Agents to update:**
- **~/.claude/**: Add `commands/`, `agents/`, `hooks/`, `CLAUDE.md`. Skip `projects/`, `statsig/`, `todos/`
- **~/.config/opencode/**: Add `opencode.json`, `agents/`, `commands/`, `skills/`, `modes/`, `plugins/`, `instructions.md`. Skip caches
- **~/.aider.conf.yml** and **~/.aider.model.settings.yml**: Sync as files
- **~/.continue/**: Sync `config.yaml`, `config.json`. Skip `sessions/`, `index/`
- **~/.cursor/**: Sync `mcp.json`, `rules`, `extensions/`
- **~/.copilot/**: Already has selective sync, verify completeness

**Implementation:**
1. Add entries to sync manifest
2. Update `_IMPORT_SYNC_MAP` with new selective entries
3. Update Dockerfile.agents symlinks
4. Add built-in excludes for skip patterns (e.g., `claude/projects`, `claude/statsig`)

**Important:** Excludes must be destination-relative per the model defined in fn-17-axl.1.

## Acceptance

- [ ] ~/.claude/ syncs: settings.json, settings.local.json, commands/, skills/, agents/, plugins/, hooks/, CLAUDE.md, .credentials.json
- [ ] ~/.claude/ skips: projects/, statsig/, todos/
- [ ] ~/.config/opencode/ syncs config files, skips caches
- [ ] ~/.aider.conf.yml synced
- [ ] ~/.aider.model.settings.yml synced
- [ ] ~/.continue/ syncs config files, skips sessions/index
- [ ] ~/.cursor/ syncs mcp.json, rules, extensions/
- [ ] All entries in sync manifest
- [ ] Built-in excludes applied destination-relative
- [ ] `cai import --dry-run` shows correct selective behavior
- [ ] Agent configs work in container after import

## Done summary
Added selective sync support for AI agent configs: Claude (commands/, agents/, hooks/, CLAUDE.md), OpenCode (selective subdirs), Aider (.aider.conf.yml, .aider.model.settings.yml), Continue (config.yaml, config.json), and Cursor (mcp.json, rules/, extensions/). Implemented @silent: prefix mechanism for built-in excludes, updated containai-init.sh volume structure, and fixed ln -sfn directory symlink pitfall.
## Evidence
- Commits: 6e9c95b, 942355f, 0c0431a, 400c0f5, a59598f, 9620fd8, 53507a2
- Tests: shellcheck -x src/lib/import.sh src/container/containai-init.sh, docker build --check -f src/container/Dockerfile.agents
- PRs:
