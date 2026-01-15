# syntax=docker/dockerfile:1
# Docker Sandbox for AI Agents

FROM docker/sandbox-templates:claude-code

# Switch to root to perform installations
USER root

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC


# Install system dependencies and build tools in one layer
# Build tools (build-essential, etc.) are REQUIRED - agents compile code!
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get autoremove -y \
    && apt-get install -y --no-install-recommends \
    # Core utilities
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \    
    jq \
    unzip \
    openssh-client \
    nano \
    socat \
    tmux \
    shellcheck \
    # Build tools 
    build-essential \
    # Python with dev headers (for building native extensions)
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    python3-tomli \
    pipx \
    gh \
    # .NET runtime dependencies
    libc6 \
    libgcc-s1 \
    libgssapi-krb5-2 \
    libicu76 \
    libssl3t64 \
    libstdc++6 \
    tzdata \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Configure bash for color prompt for both root and agent users
RUN sed -i 's/^#\s*force_color_prompt=yes/force_color_prompt=yes/' /root/.bashrc \
    && cp /root/.bashrc /home/agent/.bashrc \
    && cp /root/.profile /home/agent/.profile \
    && chown agent:agent /home/agent/.bashrc \
    && chown agent:agent /home/agent/.profile 

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

USER agent
# Build arguments for .NET channel selection
# Default to 10.0 to ensure consistent builds regardless of LTS status
# Can override with --build-arg DOTNET_CHANNEL=lts to track latest LTS
ARG DOTNET_CHANNEL=10.0

# See: https://dot.net/v1/dotnet-install.sh (official Microsoft script)
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel ${DOTNET_CHANNEL} \
    && rm /tmp/dotnet-install.sh 

# Set .NET environment variables
ENV DOTNET_ROOT=/home/agent/.dotnet
ENV PATH="${DOTNET_ROOT}:${DOTNET_ROOT}/tools:${PATH}"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
ENV DOTNET_ROLL_FORWARD=Major
ENV DOTNET_USE_POLLING_FILE_WATCHER=true
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV NUGET_XMLDOC_MODE=skip

# Install .NET workloads 
RUN dotnet workload install wasm-tools wasm-tools-net9 \
    && dotnet tool install -g PowerShell \
    && rm -rf /tmp/* 

# clear out npm config prefix to use default
ENV NPM_CONFIG_PREFIX=

# Use bash for the shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Create a script file sourced by both interactive and non-interactive bash shells
ENV NVM_DIR=/home/agent/.nvm
# Create minimal bash_env: only source nvm (no PATH, no output)
RUN printf '%s\n' \
  '[ -n "${NVM_DIR:-}" ] && [ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"' \
  > /home/agent/.bash_env
ENV BASH_ENV=/home/agent/.bashrc

# Download and install nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && source /home/agent/.nvm/nvm.sh \
    && nvm install --lts \
    && nvm alias default 'lts/*' \
    && echo node > /home/agent/.nvmrc \
    && npm install -g \
      @anthropic-ai/claude-code@latest \
      @github/copilot \
      @openai/codex \
      @google/gemini-cli \
      opencode-ai \
      typescript \
      eslint \
      prettier 

      # Point non-interactive bash at a dedicated env file
ENV BASH_ENV=/home/agent/.bash_env    

RUN curl -fsSL https://bun.com/install | bash \ 
    && curl -LsSf https://astral.sh/uv/install.sh | bash \
    && curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

# Create mount point directories so we can symlink to them
RUN  mkdir -p /home/agent/.vscode-server/data/Machine \
              /home/agent/.vscode-server/data/User \
              /home/agent/.vscode-server-insiders/data/Machine \
              /home/agent/.vscode-server-insiders/data/User  \
    # Workaround for Claude credentials symlink
    && ln -s /mnt/claude-data/.credentials.json /home/agent/.claude/.credentials.json \
    # Claude
    && rm -rf /home/agent/.claude/plugins \
    && ln -s /mnt/claude-data/claude/plugins /home/agent/.claude/plugins \
    # VS Code Insiders
    && ln -s /mnt/agent-data/vscode-server-insiders/data/Machine/settings.json /home/agent/.vscode-server-insiders/data/Machine/settings.json \
    && ln -s /mnt/agent-data/vscode-server-insiders/data/User/mcp.json /home/agent/.vscode-server-insiders/data/User/mcp.json \
    && ln -s /mnt/agent-data/vscode-server-insiders/data/User/prompts /home/agent/.vscode-server-insiders/data/User/prompts \
    && ln -s /mnt/agent-data/vscode-server-insiders/data/User/mcp /home/agent/.vscode-server-insiders/data/User/mcp \
    && ln -s /mnt/agent-data/vscode-server-insiders/extensions /home/agent/.vscode-server-insiders/extensions \
    # VS Code
    && ln -s /mnt/agent-data/vscode-server/data/Machine/settings.json /home/agent/.vscode-server/data/Machine/settings.json \
    && ln -s /mnt/agent-data/vscode-server/extensions /home/agent/.vscode-server/extensions \
    && ln -s /mnt/agent-data/vscode-server/data/User/mcp.json /home/agent/.vscode-server/data/User/mcp.json \
    && ln -s /mnt/agent-data/vscode-server/data/User/prompts /home/agent/.vscode-server/data/User/prompts \
    && ln -s /mnt/agent-data/vscode-server/data/User/mcp /home/agent/.vscode-server/data/User/mcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]