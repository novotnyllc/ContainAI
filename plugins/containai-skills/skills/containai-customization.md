# ContainAI Customization

Use this skill when: customizing containers, creating templates, adding startup hooks, configuring network policies, advanced configuration.

## Templates

Templates customize the container Dockerfile and configuration.

### Template Location

```
~/.config/containai/templates/
├── default/
│   └── Dockerfile
├── ml/
│   └── Dockerfile
└── custom/
    ├── Dockerfile
    └── hooks/
        └── startup.d/
            └── 10-setup.sh
```

### Using Templates

```bash
cai run --template ml        # Use ml template
cai run --template custom    # Use custom template
```

### Creating a Template

```bash
mkdir -p ~/.config/containai/templates/mytemplate
```

Create `Dockerfile`:

```dockerfile
ARG BASE_IMAGE=ghcr.io/containai/containai:stable
FROM ${BASE_IMAGE}

# Add custom packages
RUN apt-get update && apt-get install -y \
    my-custom-package \
    && rm -rf /var/lib/apt/lists/*

# Add custom configuration
COPY my-config /etc/my-config
```

### Template Upgrade

Upgrade templates to use the ARG BASE_IMAGE pattern (enables channel selection):

```bash
cai template upgrade              # Upgrade all templates
cai template upgrade default      # Upgrade specific template
cai template upgrade --dry-run    # Preview changes
```

### Release Channels

```bash
cai run --channel stable    # Production-ready (default)
cai run --channel nightly   # Latest features
```

## Startup Hooks

Scripts that run automatically when containers start.

### Hook Locations

**Template-level** (shared across workspaces):
```
~/.config/containai/templates/<name>/hooks/startup.d/
├── 10-common-tools.sh
└── 20-services.sh
```

**Workspace-level** (project-specific):
```
project/.containai/hooks/startup.d/
├── 30-project-deps.sh
└── 40-custom-setup.sh
```

### Execution Order

1. Template hooks first (sorted by filename)
2. Workspace hooks second (sorted by filename)

Use numeric prefixes for ordering: `10-`, `20-`, `30-`, etc.

### Creating a Hook

```bash
mkdir -p .containai/hooks/startup.d
```

Create executable script:

```bash
#!/bin/bash
# .containai/hooks/startup.d/10-setup.sh

echo "Running project setup..."

# Install project dependencies
cd /home/agent/workspace
npm install

# Start background services
npm run dev &
```

Make it executable:

```bash
chmod +x .containai/hooks/startup.d/10-setup.sh
```

### Hook Environment

- Run as `agent` user with sudo available
- Working directory: `/home/agent/workspace`
- Full access to container filesystem
- stdout/stderr logged to container init logs

### Fail-Fast

If a hook exits non-zero, container initialization fails with a clear error.

## Network Policies

Control egress traffic from containers. Opt-in feature.

### Default Behavior (No Config)

Without a `network.conf`, all egress is allowed (except private ranges).

### Policy Location

**Template-level**:
```
~/.config/containai/templates/<name>/network.conf
```

**Workspace-level**:
```
project/.containai/network.conf
```

### Config Format

```ini
[egress]
preset = package-managers
preset = git-hosts
allow = api.mycompany.com
allow = custom.domain.org
default_deny = true
```

### Presets

| Preset | Domains |
|--------|---------|
| `package-managers` | registry.npmjs.org, pypi.org, crates.io, rubygems.org, etc. |
| `git-hosts` | github.com, gitlab.com, bitbucket.org, etc. |
| `ai-apis` | api.anthropic.com, api.openai.com |

### Config Semantics

| Setting | Behavior |
|---------|----------|
| No `network.conf` | Allow all (except hard blocks) |
| `network.conf` without `default_deny` | Allow all, log allowed list |
| `default_deny = true` | Allow only listed, block rest |

### Merge Behavior

Template config provides base, workspace config extends it:

```ini
# Template: ~/.config/containai/templates/secure/network.conf
[egress]
preset = package-managers
default_deny = true

# Workspace: .containai/network.conf
[egress]
allow = api.mycompany.com
# Inherits preset and default_deny from template
```

### Hard Blocks (Always Applied)

These ranges are always blocked regardless of config:
- Private ranges (RFC 1918): 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
- Link-local: 169.254.0.0/16
- Cloud metadata: 169.254.169.254

### Examples

**Allow package managers only:**
```ini
[egress]
preset = package-managers
default_deny = true
```

**Allow specific domains:**
```ini
[egress]
allow = api.mycompany.com
allow = auth.mycompany.com
default_deny = true
```

**Development (allow all, log allowed):**
```ini
[egress]
preset = package-managers
preset = git-hosts
# default_deny = false (implicit, allows all)
```

## Configuration File

Project-specific settings in `.containai/config.toml`:

```toml
[container]
memory = "8g"
cpus = 4
template = "ml"

[import]
additional_paths = [
    "~/.npmrc",
    "~/.cargo/credentials.toml"
]

[env]
NODE_ENV = "development"
DEBUG = "true"
```

### Configuration Hierarchy

1. CLI flags (highest priority)
2. Environment variables
3. Workspace state
4. Repository config (`.containai/config.toml`)
5. User config (`~/.config/containai/config.toml`)
6. Defaults (lowest priority)

## Common Patterns

### ML/Data Science Template

```dockerfile
# ~/.config/containai/templates/ml/Dockerfile
ARG BASE_IMAGE=ghcr.io/containai/containai:stable
FROM ${BASE_IMAGE}

RUN apt-get update && apt-get install -y \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
    numpy \
    pandas \
    scikit-learn \
    jupyter
```

### Auto-Install Dependencies

```bash
#!/bin/bash
# .containai/hooks/startup.d/10-deps.sh
cd /home/agent/workspace

if [[ -f package.json ]]; then
    npm install
fi

if [[ -f requirements.txt ]]; then
    pip install -r requirements.txt
fi

if [[ -f Cargo.toml ]]; then
    cargo fetch
fi
```

### Secure Development Environment

```ini
# .containai/network.conf
[egress]
preset = package-managers
preset = git-hosts
allow = api.anthropic.com
default_deny = true
```

### Development Services

```bash
#!/bin/bash
# .containai/hooks/startup.d/20-services.sh

# Start database
docker run -d --name postgres postgres:15

# Start cache
docker run -d --name redis redis:7
```

## Gotchas

### Hook Execution Timing

Hooks run during container initialization, before SSH is available. Long-running hooks delay container readiness.

### Hook Failures

Failed hooks (non-zero exit) prevent container from starting. Use error handling:

```bash
#!/bin/bash
set -e  # Exit on error
npm install || echo "npm install failed, continuing..."
```

### Network Policy DNS Resolution

Domain names are resolved to IPs at container start. If IPs change, restart the container.

### Template Rebuild

After modifying a template Dockerfile, containers using it need rebuilding:

```bash
cai run --fresh --template mytemplate
```

Changes to hooks and network.conf are picked up on next container start (no rebuild needed).

### Runtime Mounts

Hooks and network configs are mounted at runtime, not built into the image. This means:
- Changes take effect on next container start
- No image rebuild needed
- Same image, different customizations per workspace

## Related Skills

- `containai-lifecycle` - Container management
- `containai-setup` - System configuration
- `containai-troubleshooting` - Error handling
