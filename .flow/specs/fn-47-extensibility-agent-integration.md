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

### ACP Generic Agent Support

**Actual Code Locations (verified):**
- **`src/ContainAI.Acp/AcpProxy.cs:51-54`** - Constructor validation: `if (!testMode && agent != "claude" && agent != "gemini")`
- **`src/ContainAI.Acp/Sessions/AgentSpawner.cs:32`** - Agent spawn logic (uses `cai exec` for containerized spawn)
- **`src/lib/container.sh:95-99`** - `_CONTAINAI_AGENT_TAGS` array (used for default image tags, not validation)
- **`src/lib/container.sh:116-119`** - `_containai_resolve_image()` validation (should be relaxed)

**Runtime Validation Challenge:**
When using containerized spawn (`cai exec -- <agent> --acp`), `Process.Start()` succeeds (it starts `cai`), but the agent may be missing *inside the container*. The process exits with an error code/stderr, not a start exception.

**Solution:** Container-side preflight check using positional parameters (safe from injection):
```bash
# Safe: agent passed as $1, not interpolated into shell string
bash -lc 'command -v -- "$1" >/dev/null 2>&1 || { printf "Agent '\''%s'\'' not found in container\n" "$1" >&2; exit 127; }; exec "$1" --acp' -- <agent>
```

**Image/Agent Decoupling (current state):**
- ACP agent selection is already independent of `--image-tag` (ACP spawns via `cai exec` into whatever container exists for the workspace)
- `_containai_resolve_image()` does validate agent names but this is only called when `--acp` flag used for image resolution
- The coupling that needs fixing: AcpProxy constructor and CLI help text

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
- Working directory: `/home/agent/workspace`
- Deterministic ordering: `LC_ALL=C sort`
- Non-executable files logged as warnings, skipped

**Fail-Fast Mechanism:**
Current `containai-init.service` is `Type=oneshot` and dependent services use `Wants=` (advisory). For hooks to fail container start:
- Change ssh.service.d/containai.conf and docker.service.d/containai.conf from `Wants=` to `Requires=containai-init.service`
- This makes dependent services fail if init fails, preventing the container from being usable

### Network Policy Files (Two-Level, Opt-In)

Same two-level approach for network policies. **Important:** This is opt-in - the default (no config file) allows all egress except existing hard blocks.

**Default Behavior (No Config File):**
- Allow all egress
- Except existing hard blocks: private ranges (RFC 1918), link-local (169.254.0.0/16), cloud metadata

**Opt-In Restriction (With Config File):**

```ini
# Template: ~/.config/containai/templates/my-template/network.conf
[egress]
preset = package-managers
default_deny = true

# Workspace: .containai/network.conf
[egress]
allow = api.mycompany.com
```

**Config Format:** One value per line (no comma-separated lists):
```ini
[egress]
preset = package-managers
preset = git-hosts
allow = api.anthropic.com
allow = example.com
default_deny = true
```

**Config Semantics:**
| Setting | Meaning |
|---------|---------|
| No `network.conf` | Allow all (except hard blocks) - **default** |
| `network.conf` without `default_deny` | Allow all, log allowed list (informational) |
| `network.conf` with `default_deny = true` | Allow only listed, block rest |

**Merge behavior:** Template config provides base, workspace config adds to it.

**Per-Container Rule Scoping:**
Existing network enforcement is host-side iptables on the ContainAI bridge (`DOCKER-USER` chain). Multiple containers can share the same bridge. Rules must be scoped per-container:
- Use `-s <container_ip>` to scope ACCEPT rules to specific container
- Apply rules on container start/attach (not just creation)
- Remove rules when container stops/is removed
- All stop paths must clean up rules (not just `_containai_stop_all`)

**Getting container IP reliably:**
```bash
# Handle multi-network setups
docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{if eq $k "bridge"}}{{$v.IPAddress}}{{end}}{{end}}' <container>
```

**Implementation approach:**
- New function in `network.sh` to parse network.conf (one value per line)
- Resolve domain names to IPs at container start
- Only generate blocking rules if `default_deny = true`
- Hard blocks (private ranges, metadata) always apply regardless of config
- Rules use `-s <container_ip>` and `-m comment --comment "cai:<container>"` for cleanup
- Lifecycle: add rules on start/attach, remove on stop (all stop paths)

**Presets (with full domains):**

| Preset | Domains/CIDRs |
|--------|---------------|
| `package-managers` | registry.npmjs.org, pypi.org, files.pythonhosted.org, crates.io, dl.crates.io, static.crates.io, rubygems.org |
| `git-hosts` | github.com, api.github.com, codeload.github.com, raw.githubusercontent.com, objects.githubusercontent.com, media.githubusercontent.com, gitlab.com, registry.gitlab.com, bitbucket.org |
| `ai-apis` | api.anthropic.com, api.openai.com |

**Conflict handling:** Hard blocks (private ranges, metadata) cannot be overridden. If `allow` conflicts with hard block, log warning and ignore the allow entry.

### Runtime Mounts (Not Build-Time)

Files are mounted at runtime, not copied during build.

**Actual Code Location:** `src/lib/container.sh:_containai_start_container()` (line 1452+)
**Template Resolution:** `_CAI_TEMPLATE_DIR` is templates ROOT, must build `${templates_root}/${template_name}`

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

**Note:** Mounts work for both "built template image" and "--image-tag (no template build)" flows.

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

# Create network policy (one value per line)
cat > .containai/network.conf << 'CONF'
[egress]
preset = package-managers
allow = github.com
default_deny = true
CONF

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

- `src/ContainAI.Acp/AcpProxy.cs:51-54` - Hardcoded agent check to remove (constructor)
- `src/ContainAI.Acp/Sessions/AgentSpawner.cs:32` - Agent spawn logic
- `src/lib/container.sh:95-99` - `_CONTAINAI_AGENT_TAGS` array
- `src/lib/container.sh:116-119` - `_containai_resolve_image()` validation
- `src/lib/container.sh:1452` - `_containai_start_container()` - mount logic
- `src/container/containai-init.sh` - Init script to extend
- `src/services/containai-init.service` - Init service unit
- `src/services/ssh.service.d/containai.conf` - Wants= to change to Requires=
- `src/services/docker.service.d/containai.conf` - Wants= to change to Requires=
- `src/lib/network.sh:551-714` - Existing iptables implementation
- `src/lib/template.sh` - Template directory resolution
- `docs/configuration.md:359-389` - Existing template documentation
