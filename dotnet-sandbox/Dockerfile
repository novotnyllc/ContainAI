# syntax=docker/dockerfile:1
# Docker Sandbox for AI Agents with .NET
# Provides .NET SDK with WASM workloads for Blazor/Uno development

FROM docker/sandbox-templates:claude-code

# Switch to root to perform installations
USER root

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system dependencies and build tools in one layer
# Build tools (build-essential, etc.) are REQUIRED - agents compile code!
RUN apt-get update \
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

# Install Node.js 24.x (LTS)
#RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
#    apt-get install -y nodejs && \
#    rm -rf /var/lib/apt/lists/*

# Build arguments for .NET channel selection
# Default to 10.0 to ensure consistent builds regardless of LTS status
# Can override with --build-arg DOTNET_CHANNEL=lts to track latest LTS
ARG DOTNET_CHANNEL=10.0

# Install .NET SDK using dotnet-install.sh (NOT apt)

# See: https://dot.net/v1/dotnet-install.sh (official Microsoft script)
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel ${DOTNET_CHANNEL} --install-dir /usr/share/dotnet \
    && ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh 

# Set .NET environment variables
ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH="${PATH}:/usr/share/dotnet"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
ENV DOTNET_ROLL_FORWARD=Major
ENV DOTNET_USE_POLLING_FILE_WATCHER=true
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV NUGET_XMLDOC_MODE=skip

# Install .NET workloads 
RUN dotnet workload install wasm-tools wasm-tools-net9 \
    && rm -rf /tmp/* /root/.nuget/packages /root/.dotnet/toolResolverCache

ARG POWERSHELL_VERSION="7.6.0-preview.6"
ARG POWERSHELL_RELEASE_TAG="v7.6.0-preview.6"
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    tmp_dir="$(mktemp -d)"; \
    base_url="https://github.com/PowerShell/PowerShell/releases/download/${POWERSHELL_RELEASE_TAG}"; \
    case "$arch" in \
        amd64) \
            pkg="powershell_${POWERSHELL_VERSION}-1.deb_amd64.deb"; \
            curl -fsSL "$base_url/$pkg" -o "$tmp_dir/$pkg"; \
            if ! dpkg -i "$tmp_dir/$pkg"; then \
                apt-get update; \
                apt-get install -y -f; \
                rm -rf /var/lib/apt/lists/*; \
                dpkg -i "$tmp_dir/$pkg"; \
            fi; \
            ;; \
        arm64) \
            tarball="powershell-${POWERSHELL_VERSION}-linux-arm64.tar.gz"; \
            curl -fsSL "$base_url/$tarball" -o "$tmp_dir/$tarball"; \
            install_root="/opt/microsoft/powershell/7"; \
            rm -rf "$install_root" && mkdir -p "$install_root"; \
            tar -xzf "$tmp_dir/$tarball" -C "$install_root"; \
            ln -sf "$install_root/pwsh" /usr/bin/pwsh; \
            ;; \
        *) \
            echo "Unsupported architecture for PowerShell install: $arch" >&2; \
            exit 1; \
            ;; \
    esac && \
    rm -rf "$tmp_dir"

# clear out npm config prefix to use default
ENV NPM_CONFIG_PREFIX=

USER agent
# Use bash for the shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Create a script file sourced by both interactive and non-interactive bash shells
ENV BASH_ENV=/home/agent/.bashrc
RUN touch "${BASH_ENV}"
RUN echo '. "${BASH_ENV}"' >> ~/.bashrc

# Download and install nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE="${BASH_ENV}" bash \
    && source ~/.nvm/nvm.sh \
    && nvm install --lts \
    && nvm alias default 'lts/*' \
    && echo node > .nvmrc \
    && npm install -g \
      @anthropic-ai/claude-code@latest \
      @github/copilot \
      @openai/codex \
      @google/gemini-cli \
      opencode-ai \
      typescript \
      eslint \
      prettier 
    

ENV BUN_INSTALL=/usr/share/bun
RUN curl -fsSL https://bun.com/install | bash \ 
    && curl -LsSf https://astral.sh/uv/install.sh | bash 
ENV PATH="${PATH}:${BUN_INSTALL}/bin"
ENV PATH="/home/agent/.local/bin:${PATH}"

# Create system-wide symlinks for non-interactive access (as root)
# Use nvm which to resolve the default node version deterministically
# Use explicit path instead of ~ to avoid HOME resolution issues under su
USER root
RUN NODE_BIN=$(su -s /bin/bash agent -c 'source /home/agent/.nvm/nvm.sh && nvm which default') \
    && if [ -z "$NODE_BIN" ] || [ ! -x "$NODE_BIN" ]; then \
         echo "ERROR: Failed to resolve nvm default node path" >&2; exit 1; \
       fi \
    && NODE_PATH=$(dirname "$NODE_BIN") \
    && ln -sf "$NODE_PATH/node" /usr/local/bin/node \
    && ln -sf "$NODE_PATH/npm" /usr/local/bin/npm \
    && ln -sf "$NODE_PATH/npx" /usr/local/bin/npx \
    && ln -sf "$NODE_PATH/tsc" /usr/local/bin/tsc \
    && ln -sf "$NODE_PATH/eslint" /usr/local/bin/eslint \
    && ln -sf "$NODE_PATH/prettier" /usr/local/bin/prettier \
    && ln -sf "$NODE_PATH/claude" /usr/local/bin/claude \
    && ln -sf "$NODE_PATH/codex" /usr/local/bin/codex \
    && ln -sf "$NODE_PATH/gemini" /usr/local/bin/gemini \
    && ln -sf "$NODE_PATH/copilot" /usr/local/bin/copilot 


# Install GitHub CLI, ai code agents as npm global packages in one layer
RUN <<EOF

curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg 
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null 
apt-get update 
apt-get install -y gh 
rm -rf /var/lib/apt/lists/* 
   
# Configure npm to use user-level global installation
# This installs to ~/.npm-global instead of /usr/local/lib/node_modules
#su - agent -c "mkdir -p ~/.npm-global"
#su - agent -c "npm config set prefix '~/.npm-global'"
#su - agent -c "echo 'export PATH=~/.npm-global/bin:\$PATH' >> ~/.bashrc"

# Install latest Claude Code using npm (goes to user directory)
#su - agent -c "npm install -g @anthropic-ai/claude-code@latest"
#su - agent -c "npm install -g @githubnext/github-copilot-cli"
#su - agent -c "npm install -g @openai/codex"
#su - agent -c "npm install -g @google/gemini-cli"
#su - agent -c "npm install -g opencode-ai"
#su - agent -c "npm install -g typescript"
#su - agent -c "npm install -g eslint"
#su - agent -c "npm install -g prettier"

#su - agent -c "npm cache clean --force"
rm -rf /tmp/*

# Workaround the sandbox not doing this automatically
su - agent -c "ln -s /mnt/claude-data/.credentials.json /home/agent/.claude/.credentials.json"
EOF

# Create mount point directories for volumes (per spec Volume Strategy)
# These directories will be mount targets for named volumes managed by csd wrapper
# NOTE: Must be created BEFORE the credentials symlink to avoid chown dereferencing issues
# Use restrictive permissions (0700) for dirs that may hold credentials/tokens
RUN mkdir -p /home/agent/.vscode-server \
             /home/agent/.config/gh \
             /home/agent/.claude/plugins \
    && chown -R agent:agent /home/agent/.vscode-server \                            
                            /home/agent/.config \
                            /home/agent/.claude \
    && chmod 700 /home/agent/.vscode-server \
                 /home/agent/.config/gh \
                 /home/agent/.claude

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# Final user should be agent
USER agent
# Set working directory
WORKDIR /home/agent/workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]