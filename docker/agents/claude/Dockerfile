# Claude CLI image
# Launches directly into Claude
ARG BASE_IMAGE=coding-agents:local
FROM ${BASE_IMAGE}

USER agentuser
WORKDIR /workspace

# Override entrypoint to launch Claude directly with config init
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "/usr/local/bin/init-claude-config.sh && claude"]
