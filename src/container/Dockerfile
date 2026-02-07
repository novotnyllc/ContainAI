# syntax=docker/dockerfile:1
# ContainAI - AI Agent Sandbox
#
# This is the default build target that creates the full image with all AI agents.
# For layer-specific builds, use Dockerfile.base, Dockerfile.sdks, or Dockerfile.agents.
#
# Build order (if building from scratch):
#   docker build -t containai/base -f src/container/Dockerfile.base .
#   docker build -t containai/sdks -f src/container/Dockerfile.sdks .
#   docker build -t containai/full -f src/container/Dockerfile.agents .
#   docker build -t containai -f src/container/Dockerfile .
#
# Quick build (uses pre-built layers):
#   docker build -t containai -f src/container/Dockerfile .
#
# Note: Requires Docker BuildKit (Docker 23.0+ or DOCKER_BUILDKIT=1)

# Use the full image as the default build target
# This provides the complete AI agent sandbox with all tools
ARG AGENTS_IMAGE=ghcr.io/novotnyllc/containai/agents:latest
FROM ${AGENTS_IMAGE}

# Dynamic build args at end to avoid cache invalidation
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG CONTAINAI_VERSION=unknown

LABEL org.opencontainers.image.title="ContainAI" \
      org.opencontainers.image.description="Secure AI agent sandbox with systemd, SSH, Docker-in-Docker, and AI coding agents" \
      org.opencontainers.image.url="https://github.com/novotnyllc/containai" \
      org.opencontainers.image.source="https://github.com/novotnyllc/containai" \
      org.opencontainers.image.documentation="https://github.com/novotnyllc/containai#readme" \
      org.opencontainers.image.vendor="Claire Novotny LLC" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${CONTAINAI_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

# Inherit entrypoint from base (systemd)
