# All-agents derived image
# Contains all coding agents ready to use
# Authentication comes from host mounts at runtime
ARG BASE_IMAGE=ghcr.io/yourusername/coding-agents-base:latest
FROM ${BASE_IMAGE}

USER root

# Copy MCP configuration scripts
COPY --chown=agentuser:agentuser scripts/convert-toml-to-mcp.py /usr/local/bin/convert-toml-to-mcp.py
COPY --chown=agentuser:agentuser scripts/setup-mcp-configs.sh /usr/local/bin/setup-mcp-configs.sh
COPY --chown=agentuser:agentuser scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/convert-toml-to-mcp.py /usr/local/bin/setup-mcp-configs.sh /usr/local/bin/entrypoint.sh

USER agentuser
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
