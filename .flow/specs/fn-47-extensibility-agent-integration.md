# Extensibility & Agent Integration

## Overview

Enable easy customization of ContainAI containers without requiring users to understand systemd, iptables, or Docker internals. Provide agent-friendly documentation as a skills plugin so AI agents can effectively use ContainAI.

### Core Problems
1. **ACP hardcoded to 2 agents** - Only claude/gemini work; users can't use other agents
2. **Agents don't know how to use CAI** - No skills/documentation plugin for AI agents
3. **Startup customization requires systemd knowledge** - Users must create `.service` files and symlinks
4. **Network policies require iptables knowledge** - Users must manually run iptables commands

### Goals
1. ACP works with **any** agent binary (no hardcoded list), with helpful errors for missing agents
2. Image selection decoupled from agent selection (separate concerns)
3. Skills plugin teaches agents how to use the full CAI CLI
4. Drop-in startup scripts in `.containai/` automatically run at container start
5. Drop-in network policy files generate appropriate iptables rules (opt-in)

## Scope

### In Scope
- Remove hardcoded agent validation in ACP proxy and shell wrapper
- Create containai-skills plugin with comprehensive CAI documentation
- Add startup hook directory support (`.containai/hooks/startup.d/`)
- Add network policy file support (`.containai/network.conf`)
- Default template auto-detects and includes these files
- Documentation for extensibility patterns

### Out of Scope
- MCP server implementation (agents use CLI directly)
- Python/TypeScript SDK (CLI is sufficient)
- New ACP protocol features
- Changes to ACP proxy architecture
- Agent discovery (`cai agents` command) - YAGNI; users know what they installed

## Architecture

### Startup Hooks (Two-Level)

Hooks can be defined at two levels, merged at runtime:

1. **Template-level** - Shared across all workspaces using that template
2. **Workspace-level** - Specific to one project

```
# Template-level (shared)
~/.config/containai/templates/
└── my-template/
    ├── Dockerfile
    └── hooks/
        └── startup.d/
            ├── 10-common-tools.sh    # Runs for all projects
            └── 20-services.sh

# Workspace-level (project-specific)
project/
└── .containai/
    └── hooks/
        └── startup.d/
            ├── 30-project-deps.sh    # Runs only for this project
            └── 40-custom-setup.sh
```

**Execution order:**
1. Template hooks first (sorted): `~/.config/containai/templates/<name>/hooks/startup.d/*.sh`
2. Workspace hooks second (sorted): `.containai/hooks/startup.d/*.sh`

**Implementation approach:**
- Runtime mounts (not build-time COPY) for fast iteration
- Template hooks mounted to `/etc/containai/template-hooks/`
- Workspace hooks accessed via existing workspace mount
- `containai-init.sh` runs both in order
- Scripts run as agent user with sudo available

### Network Policy Files (Two-Level, Opt-In)

Same two-level approach for network policies. **Important:** This is opt-in - the default (no config file) allows all egress except existing hard blocks.

**Default Behavior (No Config File):**
- Allow all egress
- Except existing hard blocks: private ranges (RFC 1918), link-local (169.254.0.0/16), cloud metadata

**Opt-In Restriction (With Config File):**

```ini
# Template: ~/.config/containai/templates/my-template/network.conf
[egress]
preset = package-managers  # All projects using this template get package managers
default_deny = true        # REQUIRED to enable blocking

# Workspace: .containai/network.conf
[egress]
allow = api.mycompany.com  # Project-specific additions
```

**Config Semantics:**
| Setting | Meaning |
|---------|---------|
| No `network.conf` | Allow all (except hard blocks) - **default** |
| `network.conf` without `default_deny` | Allow all, log allowed list (informational) |
| `network.conf` with `default_deny = true` | Allow only listed, block rest |

**Merge behavior:** Template config provides base, workspace config adds to it.

**Implementation approach:**
- New function in `network.sh` to parse network.conf
- Resolve domain names to IPs at container start
- Only generate blocking rules if `default_deny = true`
- Hard blocks (private ranges, metadata) always apply regardless of config
- Presets: `package-managers`, `git-hosts`, `ai-apis`

### Runtime Mounts (Not Build-Time)

Files are mounted at runtime, not copied during build:

| Source | Container Path |
|--------|---------------|
| `~/.config/containai/templates/<name>/hooks/` | `/etc/containai/template-hooks/` |
| `~/.config/containai/templates/<name>/network.conf` | `/etc/containai/template-network.conf` |
| `.containai/hooks/` | (via workspace mount) |
| `.containai/network.conf` | (via workspace mount) |

**Benefits:**
- Change hooks, restart container - no rebuild
- Same template image, different customizations per workspace
- Clear separation: template provides base, workspace overrides

### Skills Plugin Structure

```
containai-skills/
├── plugin.json
├── skills/
│   ├── containai-overview.md      # What ContainAI is, when to use it
│   ├── containai-quickstart.md    # Start a sandbox, run commands
│   ├── containai-lifecycle.md     # run, stop, status, gc
│   ├── containai-import-export.md # Config sync, data export
│   ├── containai-customization.md # Templates, hooks, network
│   └── containai-troubleshooting.md # Common issues
└── README.md
```

## Quick commands

```bash
# Test ACP with arbitrary agent
cai --acp myagent  # Should work (agent must exist in container)

# Create startup hook
mkdir -p .containai/hooks/startup.d
echo '#!/bin/bash
echo "Hello from startup hook"' > .containai/hooks/startup.d/10-hello.sh
chmod +x .containai/hooks/startup.d/10-hello.sh

# Create network policy
cat > .containai/network.conf << 'EOF'
[egress]
preset = package-managers
allow = github.com
default_deny = true
EOF

# Rebuild container with new config
cai stop && cai run
```

## Acceptance

- [ ] `cai --acp <any-agent>` works without hardcoded validation
- [ ] ACP proxy accepts any agent name, validates binary exists at runtime
- [ ] Clear, helpful error when agent binary not found: "Agent 'foo' not found in container"
- [ ] Image selection (`--image-tag`) decoupled from agent selection (`--acp`)
- [ ] containai-skills plugin published with 5+ skills covering full CLI
- [ ] Template-level hooks in `~/.config/containai/templates/<name>/hooks/startup.d/` run first
- [ ] Workspace-level hooks in `.containai/hooks/startup.d/` run second
- [ ] Startup hooks run in sorted order within each level, as agent user
- [ ] Failed startup hook fails container start with clear error
- [ ] No `network.conf` = allow all egress (except hard blocks) - unchanged default
- [ ] `network.conf` with `default_deny = true` = enforce allowlist
- [ ] `network.conf` without `default_deny` = informational only, no blocking
- [ ] Template-level `network.conf` provides base network policy
- [ ] Workspace-level `network.conf` extends template policy
- [ ] Preset support for common domains (package-managers, git-hosts)
- [ ] Runtime mounts used (no rebuild needed for hook/config changes)
- [ ] No systemd or iptables knowledge required from users
- [ ] Documentation updated for all extensibility features

## References

- `src/acp-proxy/Program.cs:31` - Hardcoded agent check to remove
- `src/containai.sh:3628-3634` - Shell wrapper agent validation
- `src/lib/container.sh:95-99` - `_CONTAINAI_AGENT_TAGS` array
- `src/container/containai-init.sh` - Init script to extend
- `src/lib/network.sh:551-714` - Existing iptables implementation
- `src/templates/example-ml.Dockerfile:32-66` - Startup service example pattern
- `docs/configuration.md:359-389` - Existing template documentation
