# Claude CLI image
# Launches directly into Claude
ARG BASE_IMAGE=coding-agents:local
FROM ${BASE_IMAGE}

USER root

# Validation script to check for Claude authentication
RUN echo '#!/usr/bin/env bash' > /usr/local/bin/validate-claude-auth.sh && \
    echo 'set -euo pipefail' >> /usr/local/bin/validate-claude-auth.sh && \
    echo 'if [ ! -d "$HOME/.config/claude" ]; then' >> /usr/local/bin/validate-claude-auth.sh && \
    echo '  echo "⚠️  WARNING: Claude authentication not found!" >&2' >> /usr/local/bin/validate-claude-auth.sh && \
    echo '  echo "   Mount ~/.config/claude from host" >&2' >> /usr/local/bin/validate-claude-auth.sh && \
    echo '  echo "   Setup Claude OAuth on host first" >&2' >> /usr/local/bin/validate-claude-auth.sh && \
    echo 'fi' >> /usr/local/bin/validate-claude-auth.sh && \
    chmod +x /usr/local/bin/validate-claude-auth.sh

# Copy Claude specific config files to ~/.config/claude/
RUN mkdir -p /home/agentuser/.config/claude
COPY --chown=agentuser:agentuser agent-configs/claude/ /home/agentuser/.config/claude/instructions/

USER agentuser
WORKDIR /workspace

# Override entrypoint to launch Claude directly
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "/usr/local/bin/validate-claude-auth.sh && claude"]
