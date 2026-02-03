# fn-49-devcontainer-integration.7 Documentation and templates

## Description

Create documentation for using ContainAI with devcontainers and provide example templates.

### Documentation: `docs/devcontainer.md`

- Prerequisites (cai setup, cai import)
- Quick start (add feature to devcontainer.json)
- Features overview (sysbox, config sync, DinD, SSH)
- Configuration options
- Troubleshooting section

### Example Templates

**Python** (`templates/devcontainer/python/.devcontainer/devcontainer.json`):
```json
{
    "name": "Python with ContainAI",
    "image": "mcr.microsoft.com/devcontainers/python:3.11",
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {}
    }
}
```

**Node.js** (`templates/devcontainer/node/.devcontainer/devcontainer.json`):
```json
{
    "name": "Node.js with ContainAI",
    "image": "mcr.microsoft.com/devcontainers/javascript-node:18",
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {}
    }
}
```

### Files to Create

- `docs/devcontainer.md` - main documentation
- `templates/devcontainer/python/.devcontainer/devcontainer.json`
- `templates/devcontainer/node/.devcontainer/devcontainer.json`
- Update `README.md` with devcontainer section

## Acceptance

- [ ] docs/devcontainer.md with complete guide
- [ ] At least 2 example templates (Python, Node.js)
- [ ] Troubleshooting section
- [ ] Reference to cai doctor for diagnostics
- [ ] Link from main README.md

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
