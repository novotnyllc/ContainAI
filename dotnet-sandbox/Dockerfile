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
# Create minimal bash_env: only source nvm (no PATH, no output)
RUN printf '%s\n' \
  '[ -n "${NVM_DIR:-}" ] && [ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"' \
  > /home/agent/.bash_env
  
USER agent
# Use bash for the shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Create a script file sourced by both interactive and non-interactive bash shells
ENV BASH_ENV=/home/agent/.bashrc
ENV NVM_DIR=/home/agent/.nvm

# Download and install nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && source /home/agent/.nvm/nvm.sh \
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

      # Point non-interactive bash at a dedicated env file
ENV BASH_ENV=/home/agent/.bash_env    

USER root
ENV BUN_INSTALL=/usr/share/bun
ENV UV_INSTALL_DIR=/usr/share/uv
RUN curl -fsSL https://bun.com/install | bash \ 
    && curl -LsSf https://astral.sh/uv/install.sh | bash 
ENV PATH="${BUN_INSTALL}/bin:${PATH}"
ENV PATH="${UV_INSTALL_DIR}/bin:${PATH}"

# Install GitHub CLI, ai code agents as npm global packages in one layer
RUN <<EOF

curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg 
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null 
apt-get update 
apt-get install -y gh 
rm -rf /var/lib/apt/lists/* 
   
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

RUN cp /root/.bashrc /home/agent/.bashrc \
    && cp /root/.profile /home/agent/.profile \
    && cp /root/.zshrc /home/agent/.zshrc \
    && chown agent:agent /home/agent/.bashrc \
    && chown agent:agent /home/agent/.profile \
    && chown agent:agent /home/agent/.zshrc

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# Final user should be agent
USER agent

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]