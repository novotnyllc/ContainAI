# fn-49-devcontainer-integration.3 Build VS Code extension (vscode-containai)

## Description

Create VS Code extension that detects ContainAI features in devcontainer.json and sets `dockerPath` to the cai-docker wrapper.

### Extension Structure

```
vscode-containai/
├── package.json
├── src/
│   └── extension.ts
├── tsconfig.json
└── README.md
```

### Extension Logic

1. **Activation**: On workspace containing devcontainer.json
2. **Detection**: Parse devcontainer.json for `containai` marker
3. **Configuration**: Set `dev.containers.dockerPath` to cai-docker path
4. **Notification**: Show info message that container will use sysbox
5. **Warning**: If cai-docker not found, show installation instructions

### Key Functions

- `findDevcontainerJson()` - locate devcontainer.json in workspace
- `hasContainAIMarkers()` - check for containai in feature references
- `findCaiDocker()` - find cai-docker wrapper path
- `configureDockerPath()` - set dev.containers.dockerPath

### Distribution

- VS Code Marketplace (marketplace.visualstudio.com)
- Open VSX (open-vsx.org)
- Bundled with cai setup

## Acceptance

- [ ] Activates when devcontainer.json present
- [ ] Detects ContainAI feature in devcontainer.json
- [ ] Sets dockerPath to cai-docker when detected
- [ ] Shows info message about sysbox sandboxing
- [ ] Shows warning when cai not installed
- [ ] Works on Windows (WSL), Mac, Linux

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
