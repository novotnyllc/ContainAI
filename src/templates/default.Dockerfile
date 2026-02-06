# ContainAI User Template
# ======================
#
# This Dockerfile customizes your ContainAI container. Edit it to add tools,
# languages, or startup scripts that you want in every new container.
#
# IMPORTANT WARNINGS:
# ------------------
# 1. Keep FROM based on ContainAI images (enforced at build time)
# 2. Runtime USER/ENTRYPOINT/CMD are enforced by the system wrapper image
# 3. Use symlink pattern for services; do not run `systemctl enable` in Dockerfile
#
# To reset to default, reinstall the template from the repo:
#   cp /path/to/containai/src/templates/default.Dockerfile \
#      ~/.config/containai/templates/default/Dockerfile
#
# Base image - ContainAI with all agents and SDKs
# Use --build-arg BASE_IMAGE to override (e.g., for nightly channel)
ARG BASE_IMAGE=ghcr.io/novotnyllc/containai:latest
FROM ${BASE_IMAGE}

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
# TEMPLATE HOOKS DIRECTORY
# =============================================================================
# This creates the target directory for runtime-mounted template hooks.
# When you add files to ~/.config/containai/templates/<name>/hooks/startup.d/,
# they are mounted here at container start (no rebuild needed).
#
# Hook execution order:
# 1. Template hooks: /etc/containai/template-hooks/startup.d/*.sh (shared)
# 2. Workspace hooks: /home/agent/workspace/.containai/hooks/startup.d/*.sh (project-specific)
#
# See docs/configuration.md for details on hook naming and ordering.
USER root
RUN mkdir -p /etc/containai/template-hooks/startup.d
USER agent

# =============================================================================
# YOUR CUSTOMIZATIONS BELOW
# =============================================================================

# Use whichever USER makes sense for your build steps.
# Runtime startup settings are enforced by the wrapper image.
