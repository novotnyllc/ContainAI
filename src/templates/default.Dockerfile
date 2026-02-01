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
