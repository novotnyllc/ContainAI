# syntax=docker/dockerfile:1
# ContainAI - AI Agent Sandbox
#
# This is the default build target that creates the full image with all AI agents.
# For layer-specific builds, use Dockerfile.base, Dockerfile.sdks, or Dockerfile.full.
#
# Build order (if building from scratch):
#   docker build -t containai/base -f src/Dockerfile.base src/
#   docker build -t containai/sdks -f src/Dockerfile.sdks src/
#   docker build -t containai/full -f src/Dockerfile.full src/
#   docker build -t containai -f src/Dockerfile src/
#
# Quick build (uses pre-built layers):
#   docker build -t containai -f src/Dockerfile src/
#
# Note: Requires Docker BuildKit (Docker 23.0+ or DOCKER_BUILDKIT=1)

# Use the full image as the default build target
# This provides the complete AI agent sandbox with all tools
FROM containai/full:latest

# Dynamic build args at end to avoid cache invalidation
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG VERSION=unknown

LABEL org.opencontainers.image.title="ContainAI" \
      org.opencontainers.image.description="Secure AI agent sandbox with systemd, SSH, Docker-in-Docker, and AI coding agents" \
      org.opencontainers.image.url="https://github.com/novotnyllc/containai" \
      org.opencontainers.image.source="https://github.com/novotnyllc/containai" \
      org.opencontainers.image.documentation="https://github.com/novotnyllc/containai#readme" \
      org.opencontainers.image.vendor="Novotny LLC" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

# Inherit entrypoint from base (systemd)
