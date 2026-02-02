# fn-47-extensibility-agent-integration.6 Documentation - Update docs for extensibility features

## Description

Update documentation to cover all new extensibility features: generic ACP, startup hooks, and network policy files.

### Docs to Update

1. **`docs/acp.md`**
   - Update "Supported Agents" to indicate any agent works
   - Add section on using custom agents
   - Update troubleshooting for generic agent errors

2. **`docs/configuration.md`**
   - Add "Startup Hooks" section explaining `.containai/hooks/startup.d/`
   - Add "Network Policies" section explaining `.containai/network.conf`
   - Include complete examples for each

3. **`README.md`**
   - Add bullet point about extensibility in features section
   - Link to configuration.md for details

4. **`docs/quickstart.md`** (if exists)
   - Mention hooks/network as optional customization

### Example Content for Hooks

```markdown
## Startup Hooks

Run custom scripts at container startup without systemd knowledge.

### Setup
\`\`\`bash
mkdir -p .containai/hooks/startup.d
cat > .containai/hooks/startup.d/10-setup.sh << 'EOF'
#!/bin/bash
npm install
redis-server --daemonize yes
EOF
chmod +x .containai/hooks/startup.d/10-setup.sh
\`\`\`

### How It Works
- Scripts run in sorted order (10-xxx before 20-xxx)
- Run as agent user with sudo available
- Non-zero exit fails container start
- Must be executable (`chmod +x`)
```

### Example Content for Network

```markdown
## Network Policies

Control egress without iptables knowledge.

### Setup
\`\`\`ini
# .containai/network.conf
[egress]
preset = package-managers
allow = github.com, api.anthropic.com
default_deny = true
\`\`\`

### Presets
- `package-managers`: npm, pypi, crates.io, rubygems
- `git-hosts`: github, gitlab, bitbucket
- `ai-apis`: anthropic, openai
```

## Acceptance

- [ ] docs/acp.md updated for generic agent support
- [ ] docs/configuration.md has Startup Hooks section
- [ ] docs/configuration.md has Network Policies section
- [ ] Each section has working examples
- [ ] README.md mentions extensibility
- [ ] All internal links valid
- [ ] No duplicate content with skills plugin

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
