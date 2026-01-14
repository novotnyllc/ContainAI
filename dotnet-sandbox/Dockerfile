# syntax=docker/dockerfile:1
# .NET 10 WASM Docker Sandbox
# Provides .NET SDK with WASM workloads for Blazor/Uno development

FROM docker/sandbox-templates:claude-code

# Build arguments for .NET channel selection
# Options: lts, sts, preview, or specific like "10.0"
ARG DOTNET_CHANNEL=lts

# Switch to root for system-level installations
USER root

# Fail fast if base image is not Ubuntu Noble
RUN . /etc/os-release && \
    if [ "$VERSION_CODENAME" != "noble" ]; then \
        echo "ERROR: Base image must be Ubuntu Noble (24.04)" >&2; \
        echo "Found: $VERSION_CODENAME" >&2; \
        exit 1; \
    fi

# Install prerequisites for .NET and PowerShell
RUN apt-get update && apt-get install -y --no-install-recommends \
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
RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel ${DOTNET_CHANNEL} --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh

# Set .NET environment variables
ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH="${PATH}:/usr/share/dotnet"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1

# Install WASM workloads
RUN dotnet workload install wasm-tools wasm-tools-net9

# Install PowerShell via Microsoft's recommended method
RUN wget -q "https://packages.microsoft.com/config/ubuntu/$(. /etc/os-release && echo $VERSION_ID)/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm /tmp/packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends powershell \
    && rm -rf /var/lib/apt/lists/*

# Install nvm and Node.js as agent user
USER agent
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
    && . ~/.nvm/nvm.sh \
    && nvm install --lts \
    && nvm alias default lts/* \
    && npm install -g typescript eslint prettier

# Create system-wide symlinks for non-interactive access (as root)
USER root
RUN ln -sf /home/agent/.nvm/versions/node/$(ls /home/agent/.nvm/versions/node)/bin/node /usr/local/bin/node \
    && ln -sf /home/agent/.nvm/versions/node/$(ls /home/agent/.nvm/versions/node)/bin/npm /usr/local/bin/npm \
    && ln -sf /home/agent/.nvm/versions/node/$(ls /home/agent/.nvm/versions/node)/bin/npx /usr/local/bin/npx

# Create /etc/profile.d/nvm.sh for login shells
RUN echo 'export NVM_DIR="/home/agent/.nvm"' > /etc/profile.d/nvm.sh \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> /etc/profile.d/nvm.sh

# Create Claude credentials symlink (same workaround as claude/Dockerfile)
USER agent
RUN mkdir -p /home/agent/.claude \
    && ln -s /mnt/claude-data/.credentials.json /home/agent/.claude/.credentials.json

# Expose ports for WASM app serving
EXPOSE 5000-5010

# Set working directory
WORKDIR /home/agent/workspace

# Final user should be agent
USER agent
