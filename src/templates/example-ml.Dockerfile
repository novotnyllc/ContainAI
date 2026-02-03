# syntax=docker/dockerfile:1.4
# ContainAI Example Template - ML Development
# ==========================================
#
# This example shows how to customize ContainAI for ML development.
# Copy this to ~/.config/containai/templates/example-ml/Dockerfile and modify.
#
# NOTE: This Dockerfile uses BuildKit heredocs (requires Docker 20.10+ with
# BuildKit enabled). ContainAI builds use BuildKit by default.
#
# IMPORTANT WARNINGS:
# ------------------
# 1. DO NOT override ENTRYPOINT - systemd is the init system and must be PID 1
# 2. DO NOT override CMD - it's set to start systemd properly
# 3. The FINAL USER must be agent - you may use USER root temporarily for installs
#
FROM ghcr.io/novotnyllc/containai:latest

# Create template hooks directory for runtime-mounted hooks
# (no rebuild needed for hook changes - just restart container)
USER root
RUN mkdir -p /etc/containai/template-hooks/startup.d

# Install CUDA toolkit (if you have NVIDIA GPU)
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
# Note: Uses printf instead of echo for portability
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

# Systemd service for GPU check
# IMPORTANT: Use symlink pattern, NOT `systemctl enable` which fails in docker build
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

# Enable the service using symlink pattern (NOT systemctl enable)
RUN ln -sf /etc/systemd/system/check-gpu.service \
    /etc/systemd/system/multi-user.target.wants/check-gpu.service
