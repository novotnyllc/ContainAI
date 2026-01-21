# fn-10-vep.17 Audit sync map for missing directories

## Description
Research and audit the `_IMPORT_SYNC_MAP` in `import.sh` to identify any missing directories that AI agents need. User suspects directories like "templates/agents" might be missing.

**Size:** S
**Files:**
- `agent-sandbox/lib/import.sh` (update _IMPORT_SYNC_MAP if needed)

## Context

Current sync map includes:
- Claude: credentials, settings, plugins, skills (but NOT templates)
- Copilot: config, mcp-config, skills
- Gemini: oauth, GEMINI.md
- Codex: config, auth, skills
- OpenCode: config, auth
- VS Code: extensions, data paths
- Shell: aliases, bashrc.d

Potentially missing (research needed):
- `~/.claude/templates/` - Custom Claude templates (if users create them)
- `~/.cursor/` and `.cursorrules` - Cursor AI IDE configs
- `~/.aider/` and `.aider.conf.yml` - Aider configs
- `~/.codeium/` - Windsurf/Codeium configs
- `~/.continue/` - Continue extension configs

## Approach

1. Research what directories each supported AI agent uses
2. Check if any common directories are missing from sync map
3. Add any missing directories following the existing pattern
4. Document why each directory is/isn't included

## Key files to reference

- `agent-sandbox/lib/import.sh:348-406` - current `_IMPORT_SYNC_MAP`
- `agent-sandbox/Dockerfile:166-253` - what agents are installed and their mount points
## Acceptance
- [ ] Researched all AI agents' config directories
- [ ] Documented which directories are synced vs excluded (with rationale)
- [ ] Added any missing essential directories to _IMPORT_SYNC_MAP
- [ ] No secrets/logs accidentally included in new entries
- [ ] Test import with new entries works correctly
## Done summary
# Task fn-10-vep.17: Audit sync map for missing directories

## Summary

Audited the `_IMPORT_SYNC_MAP` in `agent-sandbox/lib/import.sh` and the agent configuration directories in the Dockerfile to identify missing directories.

## Findings

### Current AI Agents Installed (from Dockerfile line 166-171):
- Claude Code (claude.ai)
- Codex (@openai/codex)
- Gemini CLI (@google/gemini-cli)
- Copilot (gh.io/copilot-install)
- OpenCode (opencode.ai)

### Agents NOT Installed (no sync needed):
- Cursor IDE - not installed
- Aider - not installed
- Windsurf/Codeium - not installed
- Continue extension - not installed

### Templates Directory Analysis:
- `~/.claude/templates/` - Claude does NOT have a standard templates directory. Templates are stored per-project in `.claude/` directories, not in home. The `skills/` and `plugins/` directories (which ARE synced) cover user-created components.

### Issue Found & Fixed:

**Missing: Gemini settings.json**
- The Dockerfile (line 227) creates a symlink for `~/.gemini/settings.json` to `/mnt/agent-data/gemini/settings.json`
- However, the sync map did NOT include this file
- Users would lose their Gemini CLI settings (theme, MCP servers, preferences) on container recreation
- **Fixed**: Added `/source/.gemini/settings.json:/target/gemini/settings.json:fj` to sync map

### Verification of Existing Sync Entries:

| Agent | Directories Synced | Status |
|-------|-------------------|--------|
| Claude | credentials, settings, settings.local, plugins, skills | ✅ Complete |
| Copilot | config.json, mcp-config.json, skills | ✅ Complete |
| Gemini | google_accounts, oauth_creds, GEMINI.md, **settings.json** | ✅ Now Complete |
| Codex | config.toml, auth.json, skills | ✅ Complete |
| OpenCode | ~/.config/opencode (dir), auth.json | ✅ Complete |
| VS Code | extensions, Machine/settings, User/mcp, User/prompts | ✅ Complete |
| GitHub CLI | ~/.config/gh | ✅ Complete |
| tmux | config, share dirs | ✅ Complete |
| Shell | .bash_aliases, .bashrc.d | ✅ Complete |

### Security Audit:
- No secrets/logs accidentally included
- Gemini oauth credentials properly marked with `s` flag (secret)
- No history files, tmp directories, or session data synced

## Changes Made:
- Added `settings.json` to Gemini sync entries in `_IMPORT_SYNC_MAP`
- Updated comment to mention settings sync
## Evidence
- Commits:
- Tests: source agent-sandbox/lib/import.sh - verified 31 entries load correctly
- PRs: