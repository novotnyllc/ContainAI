# GitHub Copilot CLI image
# Launches directly into Copilot interactive mode
ARG BASE_IMAGE=coding-agents:local
FROM ${BASE_IMAGE}

USER root

# Validation script to check for Copilot authentication
RUN echo '#!/usr/bin/env bash' > /usr/local/bin/validate-copilot-auth.sh && \
    echo 'set -euo pipefail' >> /usr/local/bin/validate-copilot-auth.sh && \
    echo 'if [ ! -d "$HOME/.config/github-copilot" ] && [ ! -d "$HOME/.config/gh" ]; then' >> /usr/local/bin/validate-copilot-auth.sh && \
    echo '  echo "⚠️  WARNING: GitHub Copilot authentication not found!" >&2' >> /usr/local/bin/validate-copilot-auth.sh && \
    echo '  echo "   Mount ~/.config/github-copilot or ~/.config/gh from host" >&2' >> /usr/local/bin/validate-copilot-auth.sh && \
    echo '  echo "   Run on host: gh auth login" >&2' >> /usr/local/bin/validate-copilot-auth.sh && \
    echo 'fi' >> /usr/local/bin/validate-copilot-auth.sh && \
    chmod +x /usr/local/bin/validate-copilot-auth.sh

# Copy GitHub Copilot specific config files to ~/.config/github-copilot/
RUN mkdir -p /home/agentuser/.config/github-copilot/agents
COPY --chown=agentuser:agentuser agent-configs/github-copilot/ /home/agentuser/.config/github-copilot/agents/

USER agentuser
WORKDIR /workspace

# Override entrypoint to launch Copilot directly
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "/usr/local/bin/validate-copilot-auth.sh && github-copilot-cli"]
