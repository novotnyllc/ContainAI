# Claude CLI image
# Launches directly into Claude
ARG BASE_IMAGE=containai:local
FROM ${BASE_IMAGE}

USER root

# Validation script to check for Claude authentication
RUN echo '#!/usr/bin/env bash' > /usr/local/bin/validate-claude-auth.sh && \
	echo 'set -euo pipefail' >> /usr/local/bin/validate-claude-auth.sh && \
	echo 'CLAUDE_CREDENTIALS="$HOME/.claude/.credentials.json"' >> /usr/local/bin/validate-claude-auth.sh && \
	echo 'if [ ! -s "$CLAUDE_CREDENTIALS" ]; then' >> /usr/local/bin/validate-claude-auth.sh && \
	echo '  echo "❌ Claude credential bundle missing (expected capability redemption)" >&2' >> /usr/local/bin/validate-claude-auth.sh && \
	echo '  exit 1' >> /usr/local/bin/validate-claude-auth.sh && \
	echo 'fi' >> /usr/local/bin/validate-claude-auth.sh && \
	chmod +x /usr/local/bin/validate-claude-auth.sh

# Copy Claude config template and init helper
RUN mkdir -p /home/agentuser/.config/containai/claude && \
	chown -R agentuser:agentuser /home/agentuser/.config/containai
COPY --chown=agentuser:agentuser agent-configs/claude/.claude.json /home/agentuser/.config/containai/claude/.claude.json
COPY --chown=agentuser:agentuser --chmod=755 docker/agents/claude/prepare-claude-secrets.sh /usr/local/bin/prepare-claude-secrets.sh

WORKDIR /workspace

# Override entrypoint to launch Claude directly after preparing secrets
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "/usr/local/bin/prepare-claude-secrets.sh && /usr/local/bin/validate-claude-auth.sh && agentcli-exec claude"]
