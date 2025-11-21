# All containai derived image
# Contains all agents ready to use
# Authentication comes from host mounts at runtime
ARG BASE_IMAGE=ghcr.io/novotnyllc/containai-base:latest
FROM ${BASE_IMAGE}

USER root

# Copy MCP configuration scripts from build context root
# Build context is project root, so scripts/ is directly accessible
COPY --chown=agentuser:agentuser host/utils/convert-toml-to-mcp.py /usr/local/bin/convert-toml-to-mcp.py
COPY --chown=agentuser:agentuser docker/runtime/setup-mcp-configs.sh /usr/local/bin/setup-mcp-configs.sh
COPY --chown=agentuser:agentuser docker/runtime/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=agentuser:agentuser docker/runtime/git-credential-host-helper.sh /usr/local/bin/git-credential-host-helper.sh
COPY --chown=agentuser:agentuser docker/runtime/gpg-host-proxy.sh /usr/local/bin/gpg-host-proxy.sh

RUN chmod +x /usr/local/bin/convert-toml-to-mcp.py \
    /usr/local/bin/setup-mcp-configs.sh \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/git-credential-host-helper.sh \
    /usr/local/bin/gpg-host-proxy.sh

USER agentuser
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
