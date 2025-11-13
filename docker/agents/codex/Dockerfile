# Codex CLI image
# Launches directly into Codex
ARG BASE_IMAGE=coding-agents:local
FROM ${BASE_IMAGE}

USER root

# Validation script to check for Codex authentication
RUN echo '#!/usr/bin/env bash' > /usr/local/bin/validate-codex-auth.sh && \
    echo 'set -euo pipefail' >> /usr/local/bin/validate-codex-auth.sh && \
    echo 'if [ ! -d "$HOME/.config/codex" ]; then' >> /usr/local/bin/validate-codex-auth.sh && \
    echo '  echo "⚠️  WARNING: Codex authentication not found!" >&2' >> /usr/local/bin/validate-codex-auth.sh && \
    echo '  echo "   Mount ~/.config/codex from host" >&2' >> /usr/local/bin/validate-codex-auth.sh && \
    echo '  echo "   Setup Codex OAuth on host first" >&2' >> /usr/local/bin/validate-codex-auth.sh && \
    echo 'fi' >> /usr/local/bin/validate-codex-auth.sh && \
    chmod +x /usr/local/bin/validate-codex-auth.sh

# Copy Codex specific config files to ~/.config/codex/
RUN mkdir -p /home/agentuser/.config/codex
COPY --chown=agentuser:agentuser agent-configs/codex/ /home/agentuser/.config/codex/instructions/

USER agentuser
WORKDIR /workspace

# Override entrypoint to launch Codex directly
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "/usr/local/bin/validate-codex-auth.sh && codex"]
