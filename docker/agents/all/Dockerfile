# All containai derived image
# Contains all agents ready to use
# Authentication comes from host mounts at runtime
ARG BASE_IMAGE=ghcr.io/novotnyllc/containai-base:latest
FROM ${BASE_IMAGE}

USER root

# Copy MCP configuration scripts from build context root
# Build context is project root, so scripts/ is directly accessible
# Library modules stay 644, executable scripts get --chmod=755
COPY --chown=agentuser:agentuser host/utils/_mcp_common.py /usr/local/bin/_mcp_common.py
COPY --chown=agentuser:agentuser --chmod=755 host/utils/convert_toml_to_mcp.py /usr/local/bin/convert-toml-to-mcp.py
COPY --chown=agentuser:agentuser --chmod=755 docker/runtime/setup-mcp-configs.sh /usr/local/bin/setup-mcp-configs.sh
COPY --chown=agentuser:agentuser --chmod=755 docker/runtime/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=agentuser:agentuser --chmod=755 docker/runtime/git-credential-host-helper.sh /usr/local/bin/git-credential-host-helper.sh
COPY --chown=agentuser:agentuser --chmod=755 docker/runtime/gpg-host-proxy.sh /usr/local/bin/gpg-host-proxy.sh

USER agentuser
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
