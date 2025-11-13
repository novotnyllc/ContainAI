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

USER agentuser
WORKDIR /workspace

# Override entrypoint to launch Copilot directly
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "/usr/local/bin/validate-copilot-auth.sh && github-copilot-cli"]
