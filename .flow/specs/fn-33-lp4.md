# fn-33-lp4 User Templates & Customization

## Overview

Enable users to define custom Dockerfiles for their containers, allowing them to install additional tools and customize their environment. This provides a "first time container start" mechanism without requiring manual intervention.

**Key Design:** The default template Dockerfile is included in the repo and installed as part of setup. It's a mostly-blank file with `FROM ghcr.io/novotnyllc/containai:latest` and extensive comments explaining customization options, startup scripts, and critical warnings about not overriding entrypoint.

**Note:** This epic supersedes and expands on the custom templates work in fn-18-g96.

## Scope

### In Scope
- Template directory structure at `~/.config/containai/templates/`
- **Default template shipped in repo** (not auto-generated)
- **Example template with detailed comments** showing customization patterns
- Local build for all container creation (always build user's Dockerfile)
- Layer stack validation via Dockerfile FROM parsing (warn if ContainAI not in base)
- Warning suppression via config
- Doctor template recovery (backup + restore from repo default)
- Add `--template` parameter alongside existing `--image-tag` (different semantics)

### Out of Scope
- Multi-stage template builds
- Template marketplace/sharing
- Remote template registries
- Template versioning/upgrades
- Removing `--image-tag` (retained for advanced/debugging use)

## Approach

### Template Directory Structure

The template directory uses `~/.config/containai` (consistent with existing codebase, matching `_CAI_CONFIG_DIR` in `src/lib/ssh.sh`):

```
~/.config/containai/
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
└── example-ml.Dockerfile          # Example with ML tools, startup scripts, etc.
```

During `cai setup` or first use:
1. Copy `src/templates/default.Dockerfile` to `~/.config/containai/templates/default/Dockerfile`
2. Copy `src/templates/example-ml.Dockerfile` to `~/.config/containai/templates/example-ml/Dockerfile`

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
# To reset to default: cai doctor fix template
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
# IMPORTANT: Do NOT use `systemctl enable` in Dockerfiles - systemd is not
# running during docker build. Instead, create the symlink directly:
#
# Option 1: Simple oneshot service (runs once at boot)
# ----------------------------------------------------
# COPY my-startup.sh /opt/containai/startup/my-startup.sh
# COPY my-startup.service /etc/systemd/system/my-startup.service
# RUN ln -sf /etc/systemd/system/my-startup.service \
#     /etc/systemd/system/multi-user.target.wants/my-startup.service
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

The example template (`src/templates/example-ml.Dockerfile`) shows real-world usage:

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
    && rm -rf /var/lib/apt/lists/*
USER agent

# Python ML packages
RUN pip install --user \
    torch \
    numpy \
    pandas

# Startup script to check GPU availability
COPY --chown=agent:agent <<'EOF' /opt/containai/startup/check-gpu.sh
#!/bin/bash
if command -v nvidia-smi &>/dev/null; then
    printf '[INFO] GPU detected:\n'
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
else
    printf '[INFO] No GPU detected, using CPU\n'
fi
EOF
RUN chmod +x /opt/containai/startup/check-gpu.sh

# Systemd service for GPU check - use symlink, NOT systemctl enable
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
RUN ln -sf /etc/systemd/system/check-gpu.service \
    /etc/systemd/system/multi-user.target.wants/check-gpu.service
```

### Always Build Local

Container creation flow:
1. Resolve template name (default if not specified via `--template`)
2. Check if template Dockerfile exists at `~/.config/containai/templates/{name}/Dockerfile`
3. If missing and name is "default", copy from repo
4. If missing and name is not "default", error with guidance
5. Build from user's Dockerfile using **same Docker context** as container creation:
   ```bash
   docker $context_args build -t "containai-template-${name}:local" \
       ~/.config/containai/templates/${name}/
   ```
6. Validate layer stack via FROM parsing (check if ContainAI image pattern in base)
7. If invalid, warn (unless suppressed)
8. Create container from built image using same Docker context

### Template and Container Reuse Rules

- `--template` applies **only at container creation time**
- If container already exists and `--template` is specified:
  - Check if container was built with same template (stored in label `ai.containai.template`)
  - **If label missing** (pre-existing container): allow if `--template default`, otherwise error:
    `Container was created before templates. Use --fresh to rebuild with template.`
  - **If label mismatch**: error: `Container exists with template 'X'. Use --fresh to rebuild.`
- Container stores template name as label: `ai.containai.template=<name>`

### --template and --image-tag Precedence

The `--template` and `--image-tag` flags have different purposes and can coexist:

- `--template <name>`: Builds a user-customized Dockerfile before container creation
- `--image-tag <tag>`: Overrides the base image tag (for debugging/advanced use)

**Precedence rules:**
1. If `--template` is specified, the template Dockerfile is built first
2. If `--image-tag` is also specified, it is stored as a label but **ignored for image selection** (template takes priority)
3. If only `--image-tag` is specified (no template), it controls the image directly (existing behavior)
4. Mutual exclusion is NOT enforced, but a warning is emitted if both are provided:
   `[WARN] --image-tag is ignored when --template is specified`

### Layer Stack Validation

After building, validate the Dockerfile's FROM line to verify it's based on ContainAI.

**Algorithm:**
1. Parse Dockerfile for `ARG` and `FROM` lines
2. If `FROM` uses a variable (`FROM $VAR` or `FROM ${VAR}`):
   - Look for matching `ARG VAR=value` before the FROM line
   - If found, substitute the value; if not found, emit warning (cannot validate)
3. Check if resolved base image matches accepted patterns:
   - `containai:*`
   - `ghcr.io/novotnyllc/containai*`
   - `containai-template-*:local` (chained templates)
4. If no match, emit warning; if variable unresolved, emit different warning

If not found:
```
[WARN] Your template is not based on ContainAI images.
       ContainAI features (systemd, agents, init) may not work.
       ENTRYPOINT must not be overridden or systemd won't start.

       To suppress this warning, add to config.toml:
       [template]
       suppress_base_warning = true
```

### Doctor Template Checks

Doctor template checks are **filesystem and syntax only** by default (fast):
- Check if `~/.config/containai/templates/default/Dockerfile` exists
- Check if Dockerfile has valid syntax (basic parsing, no docker daemon)
- Report missing or malformed templates

Heavy checks (actual `docker build`) are **opt-in** via:
```bash
cai doctor --build-templates
```

### Doctor Template Recovery

Interface consistent with existing doctor fix pattern:

```bash
# Check template status
$ cai doctor
[FAIL] Template 'default' missing or corrupted
       Run 'cai doctor fix template' to recover.

# Recover default template
$ cai doctor fix template
[INFO] Backing up default template to:
       ~/.config/containai/templates/default/Dockerfile.backup.20260128-143022
[INFO] Restoring default template from repo...
[OK] Template 'default' recovered.

# Recover all repo-shipped templates
$ cai doctor fix template --all

# Recover specific template by name
$ cai doctor fix template <name>
```

**Recovery rules:**
- Repo-shipped templates (`default`, `example-ml`): backup + restore from repo
- User-created templates (`cai doctor fix template <name>`): backup only, then error:
  `Template '<name>' is user-created and cannot be restored from repo. Backup saved.`
- `cai doctor fix template --all` iterates all directories under `~/.config/containai/templates/`,
  applying repo restore for known templates and backup-only for user templates

## Tasks

### fn-33-lp4.1: Define template directory structure
Create directory structure helper in `src/lib/template.sh`. Use `~/.config/containai` (matching existing `_CAI_CONFIG_DIR`). Update `src/containai.sh` to source the new library and add to `_containai_libs_exist` check.

### fn-33-lp4.2: Create template files in repo
Create `src/templates/default.Dockerfile` and `src/templates/example-ml.Dockerfile` with comprehensive comments. Use symlink pattern for systemd service enabling (NOT `systemctl enable`).

### fn-33-lp4.3: Implement template installation during setup
Copy template files from repo to user's config directory during `cai setup`. Also trigger on first use if missing.

### fn-33-lp4.4: Implement template build flow
Build user's Dockerfile before container creation using same Docker context. Tag as `containai-template-{name}:local`. Store template name as container label. Dry-run outputs `TEMPLATE_BUILD_CMD=<command>` for machine parsing.

### fn-33-lp4.5: Implement layer stack validation
Parse Dockerfile FROM line to check if base matches ContainAI patterns. Warn if not (unless suppressed). Include entrypoint warning in message.

### fn-33-lp4.6: Add warning suppression config
Add `[template].suppress_base_warning = true` config option. Update config parser to read `[template]` section.

### fn-33-lp4.7: Implement doctor template checks
Doctor diagnoses template issues (missing, parse error). Fast filesystem checks by default. Add `--build-templates` for heavy validation.

### fn-33-lp4.8: Implement doctor fix template recovery
`cai doctor fix template [--all]` backs up and restores from repo. Works for repo-shipped templates only; user templates get backup + error.

### fn-33-lp4.9: Add --template parameter
Add `--template` parameter to `run`, `shell`, `exec` commands. Coexists with `--image-tag` (different semantics). Template mismatch with existing container errors with `--fresh` guidance.

### fn-33-lp4.10: Update documentation
Document template system in quickstart and configuration docs. Include systemd symlink examples (not `systemctl enable`).

### fn-33-lp4.11: Update shell completions
Add `--template` to completion lists for run/shell/exec commands.

### fn-33-lp4.12: Add integration test
Create `tests/integration/test-templates.sh` to verify template build, doctor checks, and recovery.

## Quick commands

```bash
# View default template
cat ~/.config/containai/templates/default/Dockerfile

# Build template manually (use your Docker context if remote)
docker build -t containai-template-default:local ~/.config/containai/templates/default/

# Check template FROM line
head -20 ~/.config/containai/templates/default/Dockerfile | grep -E '^FROM'

# Test doctor recovery
mv ~/.config/containai/templates/default/Dockerfile ~/.config/containai/templates/default/Dockerfile.broken
cai doctor
cai doctor fix template
```

## Acceptance

- [ ] `src/templates/default.Dockerfile` in repo with comprehensive comments
- [ ] `src/templates/example-ml.Dockerfile` in repo with ML and startup examples
- [ ] Template files installed to `~/.config/containai/templates/` during setup
- [ ] Default template includes warnings about ENTRYPOINT/CMD/USER
- [ ] Default template uses symlink pattern for systemd (NOT `systemctl enable`)
- [ ] All container creation builds from user's Dockerfile using same Docker context
- [ ] Layer stack validation parses FROM line for ContainAI patterns
- [ ] Warning includes entrypoint/systemd note
- [ ] `cai doctor` detects template issues (fast checks by default)
- [ ] `cai doctor fix template` backs up and restores from repo
- [ ] `--template` parameter added alongside `--image-tag`
- [ ] Template mismatch errors with guidance to use `--fresh`
- [ ] Shell completions updated for `--template`
- [ ] `tests/integration/test-templates.sh` verifies template flow

## Test Plan

Smoke commands for each acceptance bullet:

1. **Template files in repo:**
   ```bash
   test -f src/templates/default.Dockerfile && test -f src/templates/example-ml.Dockerfile
   ```

2. **Template installation:**
   ```bash
   cai setup --help  # verify --skip-templates option mentioned
   test -f ~/.config/containai/templates/default/Dockerfile
   ```

3. **Build flow:**
   ```bash
   cai run --template default --fresh --dry-run 2>&1 | grep -q 'TEMPLATE_BUILD_CMD='
   ```

4. **Layer validation:**
   ```bash
   # Modify template with bad FROM, verify warning
   echo 'FROM ubuntu:latest' > ~/.config/containai/templates/test/Dockerfile
   cai run --template test --dry-run 2>&1 | grep -q 'WARN.*not based on ContainAI'
   ```

5. **Doctor checks:**
   ```bash
   rm ~/.config/containai/templates/default/Dockerfile
   cai doctor 2>&1 | grep -q 'Template.*missing'
   cai doctor fix template
   test -f ~/.config/containai/templates/default/Dockerfile
   ```

6. **Integration test:**
   ```bash
   ./tests/integration/test-templates.sh
   ```

## Dependencies

- **fn-36-rb7** (should complete first): CLI UX consistency provides workspace state
- **fn-31-gib**: Import reliability (templates need working import for configs)
- **fn-18-g96** (partial overlap): Some template work exists there; this epic supersedes it

## References

- Existing template spec: `.flow/specs/fn-18-g96.md`
- XDG Base Directory: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
- systemd service files: https://www.freedesktop.org/software/systemd/man/systemd.service.html
- Docker build context: https://docs.docker.com/build/building/context/
