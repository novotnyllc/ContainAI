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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
