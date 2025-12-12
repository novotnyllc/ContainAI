# Codex CLI image
# Launches directly into Codex
ARG BASE_IMAGE=containai:local
FROM ${BASE_IMAGE}

USER root

# Validation script to check for Codex authentication
RUN echo '#!/usr/bin/env bash' > /usr/local/bin/validate-codex-auth.sh && \
    echo 'set -euo pipefail' >> /usr/local/bin/validate-codex-auth.sh && \
    echo 'if [ ! -s "$HOME/.codex/auth.json" ]; then' >> /usr/local/bin/validate-codex-auth.sh && \
    echo '  echo "⚠️  WARNING: Codex credential bundle missing!" >&2' >> /usr/local/bin/validate-codex-auth.sh && \
    echo '  echo "   Ensure run-agent detected ~/.codex/auth.json on the host" >&2' >> /usr/local/bin/validate-codex-auth.sh && \
    echo '  echo "   or set CONTAINAI_ALLOW_AGENT_WITHOUT_SECRETS=1 to bypass" >&2' >> /usr/local/bin/validate-codex-auth.sh && \
    echo 'fi' >> /usr/local/bin/validate-codex-auth.sh && \
    chmod +x /usr/local/bin/validate-codex-auth.sh

# Copy Codex config (native TOML with MCP servers) to ~/.config/codex/
RUN mkdir -p /home/agentuser/.config/codex && \
    chown -R agentuser:agentuser /home/agentuser/.config/codex
COPY --chown=agentuser:agentuser agent-configs/codex/config.toml /home/agentuser/.config/codex/config.toml
COPY --chown=agentuser:agentuser --chmod=755 docker/agents/codex/prepare-codex-secrets.sh /usr/local/bin/prepare-codex-secrets.sh

WORKDIR /workspace

# Override entrypoint to launch Codex directly
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "/usr/local/bin/prepare-codex-secrets.sh && /usr/local/bin/validate-codex-auth.sh && agentcli-exec codex"]
