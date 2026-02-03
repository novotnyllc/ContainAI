# fn-49-devcontainer-integration.6 Publish feature and extension

## Description

Publish the ContainAI devcontainer feature to ghcr.io and the VS Code extension to marketplaces.

### Feature Publication

**Registry**: `ghcr.io/novotnyllc/containai/feature`

1. Build OCI artifact with devcontainer CLI
2. Semantic versioning (1.0.0, 1.0.1, etc.)
3. Tags: `latest`, `1`, `1.0`, `1.0.0`

CI Pipeline: `.github/workflows/publish-feature.yml`
- Trigger on `feature-v*` tags
- Use `devcontainers/action@v1`

### Extension Publication

**VS Code Marketplace**:
- Create publisher account (novotnyllc)
- Build and publish with `vsce publish`

**Open VSX**:
- Create account on open-vsx.org
- Publish with `ovsx publish`

CI Pipeline: `.github/workflows/publish-extension.yml`
- Trigger on `extension-v*` tags
- Publish to both marketplaces

### Secrets Required

- `GHCR_TOKEN` - GitHub Container Registry token
- `VSCE_PAT` - VS Code Marketplace personal access token
- `OVSX_PAT` - Open VSX personal access token

## Acceptance

- [ ] Feature published to ghcr.io/novotnyllc/containai/feature
- [ ] Feature tagged with semantic versions
- [ ] Extension published to VS Code Marketplace
- [ ] Extension published to Open VSX
- [ ] CI workflows for automated publishing
- [ ] Release notes for each version

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
