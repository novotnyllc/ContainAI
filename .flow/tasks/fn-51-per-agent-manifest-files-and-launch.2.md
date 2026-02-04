# Task fn-51.2: Add [agent] section schema with launch configuration

**Status:** pending
**Depends on:** fn-51.1

## Objective

Extend per-agent manifest format with `[agent]` section for launch configuration, including support for multiple aliases.

## Context

Currently aliases are hardcoded in Dockerfile.agents (line 161-168):
```bash
alias claude="claude --dangerously-skip-permissions"
alias codex="codex --dangerously-bypass-approvals-and-sandbox"
alias kimi="kimi --yolo"
alias kimi-cli="kimi-cli --yolo"  # Note: kimi has TWO aliases
```

This should come from manifest files. Note that kimi has both `kimi` and `kimi-cli` commands that need wrappers.

## Implementation

1. Define `[agent]` section schema:

```toml
[agent]
name = "claude"                    # Display name
binary = "claude"                  # Command to invoke (must exist in PATH)
default_args = ["--dangerously-skip-permissions"]  # Prepended to user args
aliases = []                       # Additional command names (e.g., ["kimi-cli"] for kimi)
optional = false                   # If true, wrap in command -v check (binary may not exist)
```

2. Add `[agent]` sections to manifest files that need wrappers:
   - `10-claude.toml`: `default_args = ["--dangerously-skip-permissions"]`, `optional = false`
   - `11-codex.toml`: `default_args = ["--dangerously-bypass-approvals-and-sandbox"]`, `optional = false`
   - `12-gemini.toml`: `default_args = ["--yolo"]`, `optional = true`
   - `13-copilot.toml`: `default_args = ["--yolo"]`, `optional = true`
   - `15-kimi.toml`: `default_args = ["--yolo"]`, `aliases = ["kimi-cli"]`, `optional = true`
   - `16-pi.toml`: `default_args = ["--yolo"]`, `optional = true`
   - `17-aider.toml`: Check if aider has autonomous flag; if yes, add `[agent]`, `optional = true`

3. Do NOT add `[agent]` section to:
   - `14-opencode.toml` - OpenCode has no known autonomous/yolo flag
   - `03-gh.toml` - No default args needed
   - `18-continue.toml`, `19-cursor.toml` - IDE extensions, no CLI wrapper needed
   - Infrastructure manifests (editors, shell, vscode, common, etc.)

4. Extend `src/parse-toml.py` for `[agent]` section extraction:
   - New mode: `--emit-agents` outputs JSON with agent info
   - Validates TOML syntax, required fields
   - Handles `default_args` and `aliases` arrays properly
   - Returns: `{"name": "...", "binary": "...", "default_args": [...], "aliases": [...], "optional": bool, "source_file": "..."}`

## Schema Notes

- `optional = false` (default): Wrapper generated unconditionally. Binary expected to exist.
- `optional = true`: Wrapper wrapped in `command -v` check. Safe if binary not installed.

## Acceptance Criteria

- [ ] `[agent]` section added to 6-7 manifest files that need wrappers
- [ ] Schema includes `optional` field for guarding wrapper generation
- [ ] Schema supports `aliases` array for commands with multiple names (kimi + kimi-cli)
- [ ] Wrappers only generated when `default_args` is non-empty
- [ ] `parse-toml.py` extended with `--emit-agents` mode
- [ ] Parser validates TOML syntax and required fields
- [ ] Existing `[[entries]]` parsing unchanged
- [ ] OpenCode, gh, continue, cursor have NO `[agent]` section (no wrappers needed)

## Notes

- Use `parse-toml.py` (tomllib/tomli) for proper TOML array parsing - bash regex cannot handle this
- `aliases` defaults to empty array if not specified
- `optional` defaults to false if not specified
- Do NOT add wrappers for commands with no default_args
- OpenCode explicitly does not have an autonomous flag (verified)

## Done summary
Added [agent] section schema to 6 manifest files with launch configuration (name, binary, default_args, aliases, optional fields) and extended parse-toml.py with --emit-agents mode for agent section extraction and validation.
## Evidence
- Commits: 0489dbe27725459031614c990ed1df50d9a8f30e
- Tests: python3 src/parse-toml.py --emit-agents validation, shellcheck
- PRs:
