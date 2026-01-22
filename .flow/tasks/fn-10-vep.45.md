# fn-10-vep.45 Create full Dockerfile layer (agents, gh CLI)

## Description
Create the full Dockerfile layer with AI agents and gh CLI.

**Size:** M
**Files:** src/Dockerfile.full (new), src/Dockerfile (update to multi-stage)

## Approach

1. Base from `containai/sdks:latest`
2. Install AI agents using same patterns as current Dockerfile:
   - Claude Code: `npm install -g @anthropic-ai/claude-code`
   - Gemini CLI: `npm install -g @anthropic-ai/gemini-cli`
   - Copilot: dotnet tool install
   - Codex: npm install
   - OpenCode: go install
3. Install gh CLI
4. Update main `src/Dockerfile` to be an alias/build target for full

## Key context

- Keep exact install commands from current src/Dockerfile
- gh CLI: `curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg`
## Acceptance
- [ ] `src/Dockerfile.full` created
- [ ] Builds from `containai/sdks:latest`
- [ ] All AI agents installed (claude, gemini, copilot, codex, opencode)
- [ ] gh CLI installed and `gh --version` works
- [ ] Image builds successfully
- [ ] Agents are runnable: `claude --version`, `gemini --version`, etc.
- [ ] `src/Dockerfile` updated as build alias for full
## Done summary
Created the full Dockerfile layer with AI agents (Claude, Gemini, Copilot, Codex, OpenCode, agent-browser) and gh CLI, building from containai/sdks:latest. Added containai-init systemd service for volume structure setup on first boot, with proper HOME environment handling.
## Evidence
- Commits: 51405c8, 5cca4e8, 51b0887, c1f0e4b, feb88a2
- Tests: codex impl-review SHIP verdict
- PRs: