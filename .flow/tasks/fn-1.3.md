# fn-1.3 Create devcontainer.json for VS Code Insiders

## Description
Create `devcontainer.json` supporting both VS Code Stable and Insiders with proper volume mounts and extension configurations.

### Configuration Goals

1. **Dual VS Code Support**: Works with both `code` and `code-insiders`

2. **Named volumes** for persistence:
   - VS Code Server: `docker-vscode-server` -> `/home/agent/.vscode-server`
   - VS Code Data: `docker-vscode-data` -> `/home/agent/.config/Code`
   - NuGet packages: `docker-dotnet-packages` -> `/home/agent/.nuget/packages`
   - Claude plugins: `docker-claude-plugins` -> `/home/agent/.claude/plugins` (existing)

3. **Extensions** pre-installed:
   - `anthropic.claude-code` (Claude Code)
   - `github.copilot` (GitHub Copilot)
   - `github.copilot-chat` (Copilot Chat)
   - `ms-dotnettools.csdevkit` (C# Dev Kit)
   - `ms-dotnettools.csharp` (C#)

4. **Claude extension** configuration to use local `claude` CLI

### Reference

- Reference project: https://github.com/centminmod/claude-code-devcontainers/
- Dev container spec: https://containers.dev/implementors/json_reference/
- Existing volume pattern: `claude/sync-plugins.sh:21-23`

### devcontainer.json Structure

```json
{
  "name": ".NET 10 WASM Sandbox",
  "dockerFile": "../Dockerfile",
  "remoteUser": "agent",
  "mounts": [
    "source=docker-vscode-server,target=/home/agent/.vscode-server,type=volume",
    "source=docker-vscode-data,target=/home/agent/.config/Code,type=volume",
    "source=docker-dotnet-packages,target=/home/agent/.nuget/packages,type=volume",
    "source=docker-claude-plugins,target=/home/agent/.claude/plugins,type=volume"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        "anthropic.claude-code",
        "github.copilot",
        "github.copilot-chat",
        "ms-dotnettools.csdevkit",
        "ms-dotnettools.csharp"
      ],
      "settings": {
        "claude-code.cliPath": "/usr/local/bin/claude",
        "dotnet.server.useOmnisharp": false
      }
    }
  },
  "forwardPorts": [5000, 5001],
  "postCreateCommand": "dotnet --info"
}
```

### Dual-Location Strategy

1. Include default devcontainer.json in image at `/home/agent/.devcontainer/devcontainer.json`
2. Provide template at `dotnet-wasm/.devcontainer/devcontainer.json` for users to copy to their projects

### Notes

- `dockerFile` path is relative to `.devcontainer/` directory
- Use existing `docker-claude-plugins` volume name for compatibility
- Forward ports 5000/5001 for ASP.NET Core development
- Both VS Code Stable and Insiders use same devcontainer.json format
## Acceptance
- [ ] `dotnet-wasm/.devcontainer/devcontainer.json` exists and is valid JSON
- [ ] Contains `mounts` array with VS Code Server, VS Code Data, and NuGet volumes
- [ ] Contains `customizations.vscode.extensions` with Claude, Copilot, and C# extensions
- [ ] `remoteUser` is set to `agent`
- [ ] `forwardPorts` includes 5000 and 5001
- [ ] JSON validates against devcontainer schema (no syntax errors)
- [ ] VS Code Stable (`code`) can open devcontainer
- [ ] VS Code Insiders (`code-insiders`) can open devcontainer
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
