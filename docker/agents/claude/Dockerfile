# Claude CLI image
# Launches directly into Claude
ARG BASE_IMAGE=coding-agents:local
FROM ${BASE_IMAGE}

USER root

# Validation script to check for Claude authentication
RUN echo '#!/usr/bin/env bash' > /usr/local/bin/validate-claude-auth.sh && \
	echo 'set -euo pipefail' >> /usr/local/bin/validate-claude-auth.sh && \
	echo 'CLAUDE_CREDENTIALS="$HOME/.claude/.credentials.json"' >> /usr/local/bin/validate-claude-auth.sh && \
	echo 'if [ ! -f "$CLAUDE_CREDENTIALS" ] && [ -z "${CLAUDE_API_KEY:-}" ]; then' >> /usr/local/bin/validate-claude-auth.sh && \
	echo '  echo "⚠️  WARNING: Claude authentication not found!" >&2' >> /usr/local/bin/validate-claude-auth.sh && \
	echo '  echo "   Mount ~/.claude from host or provide CLAUDE_API_KEY" >&2' >> /usr/local/bin/validate-claude-auth.sh && \
	echo 'fi' >> /usr/local/bin/validate-claude-auth.sh && \
	chmod +x /usr/local/bin/validate-claude-auth.sh

# Copy Claude config template and init helper
RUN mkdir -p /home/agentuser/.config/coding-agents/claude && \
	chown -R agentuser:agentuser /home/agentuser/.config/coding-agents
COPY --chown=agentuser:agentuser agent-configs/claude/.claude.json /home/agentuser/.config/coding-agents/claude/.claude.json
COPY docker/agents/claude/init-claude-config.sh /usr/local/bin/init-claude-config.sh
RUN chmod +x /usr/local/bin/init-claude-config.sh

USER agentuser
WORKDIR /workspace

# Override entrypoint to launch Claude directly with config init
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "/usr/local/bin/init-claude-config.sh && /usr/local/bin/validate-claude-auth.sh && claude"]
