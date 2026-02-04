# Task fn-51.2: Add [agent] section schema with launch configuration

**Status:** pending
**Depends on:** fn-51.1

## Objective

Extend per-agent manifest format with `[agent]` section for launch configuration.

## Context

Currently aliases are hardcoded in Dockerfile.agents (line 161-168):
```bash
alias claude="claude --dangerously-skip-permissions"
alias codex="codex --dangerously-bypass-approvals-and-sandbox"
alias copilot="copilot --yolo"
alias gemini="gemini --yolo"
alias kimi="kimi --yolo"
```

This should come from the manifest files so users can customize and add their own.

## Implementation

1. Define `[agent]` section schema:

```toml
[agent]
name = "claude"                    # Display name
binary = "claude"                  # Command to invoke (must exist in PATH)
default_args = ["--dangerously-skip-permissions"]  # Prepended to user args
optional = false                   # If true, no error when binary missing
```

2. Add `[agent]` sections to relevant manifest files:
   - `claude.toml`: `default_args = ["--dangerously-skip-permissions"]`
   - `codex.toml`: `default_args = ["--dangerously-bypass-approvals-and-sandbox"]`
   - `copilot.toml`: `default_args = ["--yolo"]`, `optional = true`
   - `gemini.toml`: `default_args = ["--yolo"]`, `optional = true`
   - `kimi.toml`: `default_args = ["--yolo"]`, `optional = true`
   - `gh.toml`: no default_args (just `binary = "gh"`)
   - `opencode.toml`: check if it has autonomous flag

3. Files without executable agents (editors, shell, vscode, etc.) do NOT get `[agent]` section

4. Update `parse-manifest.sh` to extract `[agent]` section fields (or create new parser)

## Acceptance Criteria

- [ ] `[agent]` section added to 6+ manifest files
- [ ] Schema documented in manifest file comments
- [ ] Parser can extract agent name, binary, default_args, optional
- [ ] Existing `[[entries]]` parsing unchanged
- [ ] Non-agent manifests (shell, vscode, etc.) remain unchanged

## Notes

- TOML arrays use `["arg1", "arg2"]` syntax
- Optional flag defaults to false if not specified
- Pi agent has `--yolo` flag too (verify)
