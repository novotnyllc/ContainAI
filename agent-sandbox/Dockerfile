# syntax=docker/dockerfile:1
# Docker Sandbox for AI Agents

FROM buildpack-deps:questing-curl AS installer
# Use bash for the shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Build arguments for .NET channel selection
# Default to 10.0 to ensure consistent builds regardless of LTS status
# Can override with --build-arg DOTNET_CHANNEL=lts to track latest LTS
ARG DOTNET_CHANNEL=10.0

ENV DOTNET_ROOT=/usr/share/dotnet 
ENV PATH=${DOTNET_ROOT}:${DOTNET_ROOT}/tools:${PATH}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \ 
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \        
        libatomic1 \
        libc6 \
        libgcc-s1 \
        libgssapi-krb5-2 \
        libicu76 \
        libssl3t64 \
        libstdc++6 \
        zlib1g \
    && curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel ${DOTNET_CHANNEL} --install-dir ${DOTNET_ROOT} 
    

# Install PowerShell global tool
RUN mkdir -p ${DOTNET_ROOT}/tools \
    && dotnet tool install PowerShell --tool-path ${DOTNET_ROOT}/tools \
    && dotnet nuget locals all --clear \
    # To reduce image size, remove the copy nupkg that nuget keeps.
    && find ${DOTNET_ROOT}/tools -print | grep -i '.*[.]nupkg$' | xargs rm    

ARG INCLUDE_DOTNET_WASM=false

RUN if [ "$INCLUDE_DOTNET_WASM" = "true" ]; then \
      dotnet workload install wasm-tools wasm-tools-net9; \
    fi \
    && dotnet --info # just to make sure things are setup
    # TODO: see if we can nuke the extras there  && find ${DOTNET_ROOT}/packs -print | grep -i '.*[.]nupkg$' | xargs rm    

FROM docker/sandbox-templates:claude-code

ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="Agent Sandbox" \
      org.opencontainers.image.description="Docker sandbox for AI coding agents" \
      org.opencontainers.image.source="https://github.com/clairernovotny/agent-sandbox" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]      
# Switch to root to perform installations
USER root

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Remove ubuntu user from base image
# Configure bash for color prompt for both root and agent users 
RUN rm -rf /home/ubuntu \ 
    && sed -i 's/^#\s*force_color_prompt=yes/force_color_prompt=yes/' /root/.bashrc \
    && cp /root/.bashrc /home/agent/.bashrc \
    && cp /root/.profile /home/agent/.profile \
    && chown agent:agent /home/agent/.bashrc \
    && chown agent:agent /home/agent/.profile \
    \
    && rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install system dependencies and build tools in one layer
# Build tools (build-essential, etc.) are REQUIRED - agents compile code!
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
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
    locales-all \
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
    libatomic1 \    
    libc6 \
    libgcc-s1 \
    libgssapi-krb5-2 \
    libicu76 \
    libssl3t64 \
    libstdc++6 \
    tzdata \
    zlib1g

USER agent

CMD [ "/bin/bash" ]
WORKDIR /home/agent
# clear out npm config prefix to use default
ENV NPM_CONFIG_PREFIX=
ENV HOME=/home/agent
# Create a script file sourced by both interactive and non-interactive bash shells
ENV NVM_DIR=${HOME}/.nvm
# Create minimal bash_env: only source nvm (no PATH, no output)
RUN printf '%s\n' \
  '[ -n "${NVM_DIR:-}" ] && [ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"' \
  > ${HOME}/.bash_env \
    && echo "alias claude='claude --dangerously-skip-permissions'" >> ${HOME}/.bash_aliases \
    && echo "alias codex='codex --dangerously-bypass-approvals-and-sandbox'" >> ${HOME}/.bash_aliases \
    && echo "alias copilot='copilot --yolo'" >> ${HOME}/.bash_aliases \
    && echo "alias gemini='gemini --yolo'" >> ${HOME}/.bash_aliases \
    && touch ${HOME}/.docker/sandbox/locks/detached.lock \
    # Add sourcing hooks to .bashrc for imported aliases and .bashrc.d scripts (idempotent)
    && { grep -qxF '[ -f ~/.bash_aliases_imported ] && . ~/.bash_aliases_imported' ${HOME}/.bashrc \
       || { echo '# Source imported bash_aliases if exists'; echo '[ -f ~/.bash_aliases_imported ] && . ~/.bash_aliases_imported'; } >> ${HOME}/.bashrc; } \
    && { grep -qxF 'if [ -d ~/.bashrc.d ]; then for f in ~/.bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done; fi' ${HOME}/.bashrc \
       || { echo '# Source all scripts in .bashrc.d if directory exists'; echo 'if [ -d ~/.bashrc.d ]; then for f in ~/.bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done; fi'; } >> ${HOME}/.bashrc; }
ENV BASH_ENV=${HOME}/.bash_env

RUN curl -fsSL https://bun.com/install | bash \
    && curl -LsSf https://astral.sh/uv/install.sh | bash

# Download and install nvm
RUN --mount=type=cache,target=${HOME}/.npm/_cacache,uid=1000,gid=1000 \
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && source ${HOME}/.nvm/nvm.sh \
    && nvm install --lts \
    && nvm alias default 'lts/*' \
    && echo node > ${HOME}/.nvmrc \
    && npm install -g typescript eslint prettier


ENV PATH="${HOME}/.bun/bin:${PATH}"

# Download and install the latest agents
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && bun install -g --trust @openai/codex @google/gemini-cli agent-browser  \
    && curl -fsSL https://gh.io/copilot-install | bash \
    && curl -fsSL https://opencode.ai/install | bash \
    && rm -rf /tmp/*

# Create mount point directories so we can symlink to them
RUN  mkdir -p ${HOME}/.vscode-server/data/Machine \
              ${HOME}/.vscode-server/data/User \
              ${HOME}/.vscode-server-insiders/data/Machine \
              ${HOME}/.vscode-server-insiders/data/User  \
              ${HOME}/.copilot  \
              ${HOME}/.gemini \
              ${HOME}/.opencode  \
              ${HOME}/.codex  \
    \
    # folders that need to be removed before we can symlink to them
    # Remove the plugins folder on create as we'll be symlinking it to the mount point
    # We do this here instead of in the entryoint as this is part of our build
    # The entrypoint will touch the files to ensure they exist at runtime on the volume
    \
    && sudo mkdir -p /mnt/agent-data \
    && sudo chown -R agent:agent /mnt/agent-data \
    \
    # Claude
    && mkdir -p /mnt/agent-data/claude/skills \
    && mkdir -p /mnt/agent-data/claude/plugins \
    && mv ${HOME}/.claude.json /mnt/agent-data/claude/claude.json \
    && ln -sfn /mnt/agent-data/claude/credentials.json ${HOME}/.claude/.credentials.json \
    && ln -sfn /mnt/agent-data/claude/claude.json ${HOME}/.claude.json \
    && ln -sfn /mnt/agent-data/claude/settings.json ${HOME}/.claude/settings.json \
    && ln -sfn /mnt/agent-data/claude/plugins ${HOME}/.claude/plugins \
    && ln -sfn /mnt/agent-data/claude/skills ${HOME}/.claude/skills \
    \
    # VS Code Insiders
    && ln -sfn /mnt/agent-data/vscode-server-insiders/data/Machine/settings.json ${HOME}/.vscode-server-insiders/data/Machine/settings.json \
    && ln -sfn /mnt/agent-data/vscode-server-insiders/data/User/mcp.json ${HOME}/.vscode-server-insiders/data/User/mcp.json \
    && ln -sfn /mnt/agent-data/vscode-server-insiders/data/User/prompts ${HOME}/.vscode-server-insiders/data/User/prompts \
    && ln -sfn /mnt/agent-data/vscode-server-insiders/data/User/mcp ${HOME}/.vscode-server-insiders/data/User/mcp \
    && ln -sfn /mnt/agent-data/vscode-server-insiders/extensions ${HOME}/.vscode-server-insiders/extensions \
    \
    # VS Code
    && ln -sfn /mnt/agent-data/vscode-server/data/Machine/settings.json ${HOME}/.vscode-server/data/Machine/settings.json \
    && ln -sfn /mnt/agent-data/vscode-server/extensions ${HOME}/.vscode-server/extensions \
    && ln -sfn /mnt/agent-data/vscode-server/data/User/mcp.json ${HOME}/.vscode-server/data/User/mcp.json \
    && ln -sfn /mnt/agent-data/vscode-server/data/User/prompts ${HOME}/.vscode-server/data/User/prompts \
    && ln -sfn /mnt/agent-data/vscode-server/data/User/mcp ${HOME}/.vscode-server/data/User/mcp \
    \
    # Copilot
    && ln -sfn /mnt/agent-data/copilot/config.json ${HOME}/.copilot/config.json \
    && ln -sfn /mnt/agent-data/copilot/mcp-config.json ${HOME}/.copilot/mcp-config.json \
    && rm -rf ${HOME}/.copilot/skills \
    && ln -sfn /mnt/agent-data/copilot/skills ${HOME}/.copilot/skills \
    \
    # Gemini
    && ln -sfn /mnt/agent-data/gemini/google_accounts.json ${HOME}/.gemini/google_accounts.json \
    && ln -sfn /mnt/agent-data/gemini/oauth_creds.json ${HOME}/.gemini/oauth_creds.json \
    && ln -sfn /mnt/agent-data/gemini/settings.json ${HOME}/.gemini/settings.json \
    && ln -sfn /mnt/agent-data/gemini/GEMINI.md ${HOME}/.gemini/GEMINI.md \
    \
    # Codex
    && mkdir -p /mnt/agent-data/codex \
    && ln -sfn /mnt/agent-data/codex/auth.json ${HOME}/.codex/auth.json \
    && ln -sfn /mnt/agent-data/codex/config.toml ${HOME}/.codex/config.toml \
    && rm -rf ${HOME}/.codex/skills \
    && ln -sfn /mnt/agent-data/codex/skills ${HOME}/.codex/skills \
    \
    # tmux (legacy location)
    && mkdir -p /mnt/agent-data/tmux \
    && ln -sfn /mnt/agent-data/tmux/.tmux.conf ${HOME}/.tmux.conf \
    && rm -rf ${HOME}/.tmux \
    && ln -sfn /mnt/agent-data/tmux/.tmux ${HOME}/.tmux \
    \
    # Shell configs
    && mkdir -p /mnt/agent-data/shell \
    && ln -sfn /mnt/agent-data/shell/.bash_aliases ${HOME}/.bash_aliases_imported \
    && rm -rf ${HOME}/.bashrc.d \
    && ln -sfn /mnt/agent-data/shell/.bashrc.d ${HOME}/.bashrc.d \
    \
    # OpenCode data (XDG_DATA_HOME for auth.json)
    && mkdir -p ${HOME}/.local/share/opencode \
    && mkdir -p /mnt/agent-data/local/share/opencode \
    && ln -sfn /mnt/agent-data/local/share/opencode/auth.json ${HOME}/.local/share/opencode/auth.json \
    \
    # Config (rename to 'config' on move to match symlink target)
    && mv ${HOME}/.config /mnt/agent-data/config \
    && ln -sfn /mnt/agent-data/config ${HOME}/.config


COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /home/agent
ENV \
    # Do not generate certificate
    DOTNET_GENERATE_ASPNET_CERTIFICATE=false \
    # Do not show first run text
    DOTNET_NOLOGO=true \    
    # Enable correct mode for dotnet watch (only mode supported in a container)
    DOTNET_USE_POLLING_FILE_WATCHER=true \
    # Skip extraction of XML docs - generally not useful within an image/container - helps performance
    NUGET_XMLDOC_MODE=skip \
    # Workaround for https://github.com/PowerShell/PowerShell/issues/20685
    DOTNET_ROLL_FORWARD=Major \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_ROOT=${HOME}/.dotnet 
ENV PATH=${DOTNET_ROOT}:${DOTNET_ROOT}/tools:${PATH}
COPY --from=installer --chown=agent /usr/share/dotnet ${HOME}/.dotnet

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]