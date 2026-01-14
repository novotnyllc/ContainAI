# syntax=docker/dockerfile:1
# .NET 10 WASM Docker Sandbox
# Provides .NET SDK with WASM workloads for Blazor/Uno development

FROM docker/sandbox-templates:claude-code

# Build arguments for .NET channel selection
# Default to 10.0 to ensure consistent builds regardless of LTS status
# Can override with --build-arg DOTNET_CHANNEL=lts to track latest LTS
ARG DOTNET_CHANNEL=10.0

# Switch to root for system-level installations
USER root

# Fail fast if base image is not Ubuntu Noble
RUN . /etc/os-release && \
    if [ "$VERSION_CODENAME" != "noble" ]; then \
        echo "ERROR: Base image must be Ubuntu Noble (24.04)" >&2; \
        echo "Found: $VERSION_CODENAME" >&2; \
        exit 1; \
    fi

# Install prerequisites for .NET, PowerShell, and dotnet-install.sh
# bash and tar are required by dotnet-install.sh for extraction
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    tar \
    gzip \
    curl \
    wget \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    libc6 \
    libgcc-s1 \
    libicu74 \
    libssl3 \
    libstdc++6 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Install .NET SDK using dotnet-install.sh (NOT apt)
# NOTE: Supply chain risk - downloads script from Microsoft. For production use,
# consider vendoring the script or verifying a known checksum.
# See: https://dot.net/v1/dotnet-install.sh (official Microsoft script)
# Verify .NET 10 is installed per acceptance criteria
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel ${DOTNET_CHANNEL} --install-dir /usr/share/dotnet \
    && ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh \
    && dotnet --version \
    && if ! dotnet --version | grep -qE '^10\.'; then \
         echo "ERROR: Expected .NET 10.x, got $(dotnet --version)" >&2; \
         exit 1; \
       fi

# Set .NET environment variables
ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH="${PATH}:/usr/share/dotnet"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
ENV NUGET_XMLDOC_MODE=skip

# Install WASM workloads
# wasm-tools is required (hard fail)
# wasm-tools-net9 is optional (fail-open for forward compatibility)
RUN dotnet workload install wasm-tools \
    && dotnet workload list | grep -E '^[[:space:]]*wasm-tools([[:space:]]|$)'

# Install wasm-tools-net9 (optional, fail-open)
RUN dotnet workload install wasm-tools-net9 \
    || echo "Note: wasm-tools-net9 not available (may not be needed for .NET 10+)"

# Install PowerShell via Microsoft's recommended method and verify
RUN wget -q "https://packages.microsoft.com/config/ubuntu/$(. /etc/os-release && echo $VERSION_ID)/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm /tmp/packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends powershell \
    && rm -rf /var/lib/apt/lists/* \
    && pwsh --version

# Verify agent user has expected UID (inherited from base image)
RUN id -u agent | grep -x 1000 || (echo "ERROR: agent user must have UID 1000" >&2 && exit 1)

# Use bash for nvm-related commands (nvm.sh requires bash, not dash)
SHELL ["/bin/bash", "-c"]

# Install nvm and Node.js as agent user
# NOTE: Supply chain risk - downloads script from GitHub. Version v0.40.1 is pinned.
# For production use, consider verifying the script checksum or vendoring it.
# See: https://github.com/nvm-sh/nvm/releases
USER agent
RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh -o /tmp/nvm-install.sh \
    && bash /tmp/nvm-install.sh \
    && rm /tmp/nvm-install.sh \
    && source ~/.nvm/nvm.sh \
    && nvm install --lts \
    && nvm alias default lts/* \
    && npm install -g typescript@5 eslint@8 prettier@3

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
    && ln -sf "$NODE_PATH/prettier" /usr/local/bin/prettier

# Create /etc/profile.d/nvm.sh for login shells with explicit nvm use
RUN echo 'export NVM_DIR="/home/agent/.nvm"' > /etc/profile.d/nvm.sh \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm use default >/dev/null 2>&1' >> /etc/profile.d/nvm.sh

# Verify Node.js installation via symlink (as root)
RUN /usr/local/bin/node --version

# Verify Node.js installation as agent user (login shell environment)
USER agent
RUN bash -lc "node --version" \
    && bash -lc "nvm --version" \
    && bash -lc "tsc --version && eslint --version && prettier --version"

# Switch back to root for directory setup
USER root

# Ensure workspace directory exists with correct ownership
RUN mkdir -p /home/agent/workspace \
    && chown -R agent:agent /home/agent/workspace

# Create mount point directories for volumes (per spec Volume Strategy)
# These directories will be mount targets for named volumes managed by csd wrapper
# NOTE: Must be created BEFORE the credentials symlink to avoid chown dereferencing issues
# Use restrictive permissions (0700) for dirs that may hold credentials/tokens
RUN mkdir -p /home/agent/.vscode-server \
             /home/agent/.nuget \
             /home/agent/.config/gh \
             /home/agent/.claude/plugins \
    && chown -R agent:agent /home/agent/.vscode-server \
                            /home/agent/.nuget \
                            /home/agent/.config \
                            /home/agent/.claude \
    && chmod 700 /home/agent/.vscode-server \
                 /home/agent/.nuget \
                 /home/agent/.config/gh \
                 /home/agent/.claude

# Create Claude credentials symlink (same workaround as claude/Dockerfile)
# Done AFTER mount point creation to avoid symlink target being affected by chown
USER agent
RUN ln -sf /mnt/claude-data/.credentials.json /home/agent/.claude/.credentials.json

# Expose primary port for WASM app serving (additional ports available on demand)
EXPOSE 5000

# Set working directory
WORKDIR /home/agent/workspace

# Final user should be agent
USER agent
