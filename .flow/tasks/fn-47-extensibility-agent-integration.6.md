# fn-47-extensibility-agent-integration.6 Documentation - Update docs for extensibility features

## Description

Update documentation to cover all new extensibility features: generic ACP, startup hooks, and network policy files.

### Docs to Update

1. **docs/acp.md**
   - Update "Supported Agents" to indicate any agent works
   - Add section on using custom agents
   - Update troubleshooting for generic agent errors

2. **docs/configuration.md**
   - Add "Startup Hooks" section explaining .containai/hooks/startup.d/
   - Add "Network Policies" section explaining .containai/network.conf
   - Include complete examples for each

3. **README.md**
   - Add bullet point about extensibility in features section
   - Link to configuration.md for details

4. **docs/quickstart.md** (if exists)
   - Mention hooks/network as optional customization

### Example Content for Hooks

The Startup Hooks section should include:

- Directory structure: .containai/hooks/startup.d/
- Script naming convention (10-xxx, 20-xxx for ordering)
- Scripts run as agent user with sudo available
- Non-zero exit fails container start
- Must be executable (chmod +x)

Example script creation:
```bash
mkdir -p .containai/hooks/startup.d
cat > .containai/hooks/startup.d/10-setup.sh << 'SCRIPT'
#!/bin/bash
npm install
redis-server --daemonize yes
SCRIPT
chmod +x .containai/hooks/startup.d/10-setup.sh
```

### Example Content for Network

The Network Policies section should include:

- Config file location: .containai/network.conf
- INI format with [egress] section
- One value per line (no comma-separated lists)
- Presets available: package-managers, git-hosts, ai-apis
- default_deny = true required to enable blocking

Example configuration:
```ini
# .containai/network.conf
[egress]
preset = package-managers
preset = git-hosts
allow = github.com
allow = api.anthropic.com
default_deny = true
```

Semantics table:
| Setting | Behavior |
|---------|----------|
| No network.conf | Allow all egress (default) |
| Without default_deny | Informational only, no blocking |
| With default_deny = true | Enforce allowlist |

Presets expand to:
- package-managers: npm, pypi, crates.io, rubygems
- git-hosts: github, gitlab, bitbucket
- ai-apis: anthropic, openai

## Acceptance

- [ ] docs/acp.md updated for generic agent support
- [ ] docs/configuration.md has Startup Hooks section
- [ ] docs/configuration.md has Network Policies section
- [ ] Each section has working examples
- [ ] Network config examples use one value per line format
- [ ] README.md mentions extensibility
- [ ] All internal links valid
- [ ] No duplicate content with skills plugin

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
