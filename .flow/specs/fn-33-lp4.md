# fn-33-lp4 User Templates & Customization

## Overview

Enable users to define custom Dockerfiles for their containers, allowing them to install additional tools and customize their environment. This provides a "first time container start" mechanism without requiring manual intervention.

**Key Design:** The default template Dockerfile is included in the repo and installed as part of setup. It's a mostly-blank file with `FROM containai:latest` and extensive comments explaining customization options, startup scripts, and critical warnings about not overriding entrypoint.

**Note:** This epic supersedes and expands on the custom templates work in fn-18-g96.

## Scope

### In Scope
- Template directory structure at `~/.config/containai/templates/`
- **Default template shipped in repo** (not auto-generated)
- **Example template with detailed comments** showing customization patterns
- Local build for all container creation (always build user's Dockerfile)
- Layer stack validation (warn if ContainAI not in base)
- Warning suppression via config
- Doctor template recovery (backup + restore from repo default)
- Rename `--image/--tag` parameter to `--template` (no backward compatibility)

### Out of Scope
- Multi-stage template builds
- Template marketplace/sharing
- Remote template registries
- Template versioning/upgrades

## Approach

### Template Directory Structure

```
${XDG_CONFIG_HOME:-~/.config}/containai/
├── config.toml                    # Main config file
└── templates/
    ├── default/
    │   └── Dockerfile             # Installed from repo, user can customize
    └── my-custom/
        └── Dockerfile             # User-created
```

### Repo Template Files

In the ContainAI repo at `src/templates/`:
```
src/templates/
├── default.Dockerfile             # The default template
└── example.Dockerfile             # Example with ML tools, startup scripts, etc.
```

During `cai setup` or first use:
1. Copy `src/templates/default.Dockerfile` to `~/.config/containai/templates/default/Dockerfile`
2. Copy `src/templates/example.Dockerfile` to `~/.config/containai/templates/example/Dockerfile`

### Default Template Content

The default template (`src/templates/default.Dockerfile`):

```dockerfile
# ContainAI User Template
# ======================
#
# This Dockerfile customizes your ContainAI container. Edit it to add tools,
# languages, or startup scripts that you want in every new container.
#
# IMPORTANT WARNINGS:
# ------------------
# 1. DO NOT override ENTRYPOINT - systemd is the init system and must be PID 1
# 2. DO NOT override CMD - it's set to start systemd properly
# 3. DO NOT change the USER - agent user (UID 1000) is required for permissions
#
# To reset to default: cai doctor fix --template
#
# Base image - ContainAI with all agents and SDKs
FROM ghcr.io/novotnyllc/containai:latest

# =============================================================================
# INSTALL ADDITIONAL TOOLS
# =============================================================================
# Uncomment and modify as needed:
#
# System packages (as root):
# USER root
# RUN apt-get update && apt-get install -y \
#     your-package \
#     another-package \
#     && rm -rf /var/lib/apt/lists/*
# USER agent
#
# Node packages (as agent):
# RUN npm install -g prettier eslint typescript
#
# Python packages (as agent):
# RUN pip install --user black ruff mypy
#
# Rust tools (as agent):
# RUN cargo install ripgrep fd-find

# =============================================================================
# CUSTOM STARTUP SCRIPTS (systemd services)
# =============================================================================
# To run scripts when the container starts, create a systemd service.
#
# Option 1: Simple oneshot service (runs once at boot)
# ----------------------------------------------------
# COPY my-startup.sh /opt/containai/startup/my-startup.sh
# COPY my-startup.service /etc/systemd/system/my-startup.service
# RUN systemctl enable my-startup.service
#
# Example my-startup.service:
#   [Unit]
#   Description=My Custom Startup Script
#   After=containai-init.service
#
#   [Service]
#   Type=oneshot
#   ExecStart=/opt/containai/startup/my-startup.sh
#   User=agent
#
#   [Install]
#   WantedBy=multi-user.target
#
# Option 2: Long-running service (daemon)
# --------------------------------------
# Create a service file that runs continuously:
#   [Service]
#   Type=simple
#   ExecStart=/path/to/your/daemon
#   Restart=always
#   User=agent

# =============================================================================
# ENVIRONMENT VARIABLES
# =============================================================================
# Set environment variables for all sessions:
#
# ENV MY_VAR=value
# ENV PATH="/custom/path:${PATH}"

# =============================================================================
# YOUR CUSTOMIZATIONS BELOW
# =============================================================================

```

### Example Template Content

The example template (`src/templates/example.Dockerfile`) shows real-world usage:

```dockerfile
# ContainAI Example Template - ML Development
# ==========================================
#
# This example shows how to customize ContainAI for ML development.
# Copy this to ~/.config/containai/templates/ml/Dockerfile and modify as needed.
#
FROM ghcr.io/novotnyllc/containai:latest

# Install CUDA toolkit (if you have NVIDIA GPU)
USER root
RUN apt-get update && apt-get install -y \
    nvidia-cuda-toolkit \
    libcudnn8 \
    && rm -rf /var/lib/apt/lists/*
USER agent

# Python ML packages
RUN pip install --user \
    torch \
    transformers \
    numpy \
    pandas \
    jupyter

# Startup script to check GPU availability
COPY --chown=agent:agent <<'EOF' /opt/containai/startup/check-gpu.sh
#!/bin/bash
if command -v nvidia-smi &>/dev/null; then
    echo "[INFO] GPU detected:"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
else
    echo "[INFO] No GPU detected, using CPU"
fi
EOF
RUN chmod +x /opt/containai/startup/check-gpu.sh

# Systemd service for GPU check
COPY --chown=root:root <<'EOF' /etc/systemd/system/check-gpu.service
[Unit]
Description=Check GPU availability
After=containai-init.service

[Service]
Type=oneshot
ExecStart=/opt/containai/startup/check-gpu.sh
User=agent

[Install]
WantedBy=multi-user.target
EOF
RUN systemctl enable check-gpu.service
```

### Always Build Local

Container creation flow:
1. Resolve template name (default if not specified)
2. Check if template Dockerfile exists
3. If missing and name is "default", copy from repo
4. If missing and name is not "default", error
5. Build from user's Dockerfile (tagged `containai-template-{name}:local`)
6. Validate layer stack (check if ContainAI image in parents)
7. If invalid, warn (unless suppressed)
8. Create container from built image

### Layer Stack Validation

After building template image, inspect layers to verify it's based on ContainAI.

If not found:
```
[WARN] Your template is not based on ContainAI images.
       ContainAI features (systemd, agents, init) may not work.
       ENTRYPOINT must not be overridden or systemd won't start.

       To suppress this warning, add to config.toml:
       [template]
       suppress_base_warning = true
```

### Doctor Template Recovery

When template build fails or is corrupted:

```bash
$ cai doctor
[FAIL] Template 'default' build failed
       Build error: invalid syntax at line 15

       Run 'cai doctor fix' to recover.

$ cai doctor fix
[INFO] Backing up default template to:
       ~/.config/containai/templates/default/Dockerfile.backup.20260128-143022
[INFO] Restoring default template from repo...
[OK] Template 'default' recovered.
```

## Tasks

### fn-33-lp4.1: Create template files in repo
Create `src/templates/default.Dockerfile` and `src/templates/example.Dockerfile` with comprehensive comments.

### fn-33-lp4.2: Define template directory structure
Create directory structure at XDG_CONFIG_HOME. Document layout in code and docs.

### fn-33-lp4.3: Implement template installation during setup
Copy template files from repo to user's config directory during `cai setup` or first use.

### fn-33-lp4.4: Implement template build flow
Build user's Dockerfile before container creation. Tag as `containai-template-{name}:local`.

### fn-33-lp4.5: Implement layer stack validation
After build, check if ContainAI images are in layer history. Warn if not. Include entrypoint warning.

### fn-33-lp4.6: Add warning suppression config
Config option `[template].suppress_base_warning = true` to disable validation warning.

### fn-33-lp4.7: Implement doctor template checks
Doctor diagnoses template issues (missing, build failure). Reports actionable fixes.

### fn-33-lp4.8: Implement doctor fix --template recovery
Backup corrupted template with timestamp, restore from repo. Works for any template name.

### fn-33-lp4.9: Rename image/tag to template parameter
Remove `--image` and `--tag` from all commands. Add `--template` parameter.

### fn-33-lp4.10: Update documentation
Document template system in quickstart and configuration docs. Include systemd service examples.

## Quick commands

```bash
# View default template
cat ~/.config/containai/templates/default/Dockerfile

# Build template manually
docker build -t containai-template-default:local ~/.config/containai/templates/default/

# Check layer history
docker image history containai-template-default:local

# Test doctor recovery
mv ~/.config/containai/templates/default/Dockerfile ~/.config/containai/templates/default/Dockerfile.broken
cai doctor
cai doctor fix
```

## Acceptance

- [ ] `src/templates/default.Dockerfile` in repo with comprehensive comments
- [ ] `src/templates/example.Dockerfile` in repo with ML and startup examples
- [ ] Template files installed to `~/.config/containai/templates/` during setup
- [ ] Default template includes warnings about ENTRYPOINT/CMD/USER
- [ ] Default template includes commented examples for tools and systemd services
- [ ] All container creation builds from user's Dockerfile
- [ ] Layer stack validation warns if not based on ContainAI
- [ ] Warning includes entrypoint/systemd note
- [ ] `cai doctor` detects template issues
- [ ] `cai doctor fix` backs up and restores from repo
- [ ] `--template` parameter replaces `--image`/`--tag`

## Dependencies

- **fn-36-rb7** (should complete first): CLI UX consistency provides workspace state, `--template` parameter semantics
- **fn-31-gib**: Import reliability (templates need working import for configs)
- **fn-18-g96** (partial overlap): Some template work exists there; this epic supersedes it

## References

- Existing template spec: `.flow/specs/fn-18-g96.md`
- XDG Base Directory: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
- systemd service files: https://www.freedesktop.org/software/systemd/man/systemd.service.html
- Docker build context: https://docs.docker.com/build/building/context/
