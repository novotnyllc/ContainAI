# Base image for coding agents container
# This is a DEVELOPMENT container - agents need build tools to compile code!
FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system dependencies and build tools in one layer
# Build tools (build-essential, etc.) are REQUIRED - agents compile code!
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    sudo \
    zsh \
    vim \
    nano \
    jq \
    unzip \
    # Build tools (REQUIRED for development)
    build-essential \
    # Python with dev headers (for building native extensions)
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # Playwright browser dependencies (--with-deps needs these available)
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libatspi2.0-0 \
    libxshmfence1 \
    # .NET runtime dependencies
    libc6 \
    libgcc-s1 \
    libgssapi-krb5-2 \
    libicu74 \
    libssl3 \
    libstdc++6 \
    libunwind8 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x (required for MCP servers and building Node projects)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install .NET SDKs (agents need SDK, not just runtime, to build C# projects)
RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh && \
    chmod +x dotnet-install.sh && \
    ./dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet && \
    ./dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet && \
    ./dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet && \
    rm dotnet-install.sh && \
    ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH="${PATH}:/usr/share/dotnet"

# Install .NET workloads (MAUI, Blazor, WASM, etc.)
RUN dotnet workload install aspire maui wasm-tools ios android maccatalyst tvos || \
    echo "⚠️  Some workloads may have failed (expected for some platforms)"

# Install PowerShell
RUN curl -sSL https://aka.ms/install-powershell.sh -o install-powershell.sh && \
    chmod +x install-powershell.sh && \
    ./install-powershell.sh && \
    rm install-powershell.sh

# Copy .NET preview installer script
COPY --chown=root:root scripts/runtime/install-dotnet-preview.sh /usr/local/bin/install-dotnet-preview.sh
RUN chmod +x /usr/local/bin/install-dotnet-preview.sh

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Install Playwright browsers and dependencies (--with-deps handles all system packages)
RUN npm install -g \
    @playwright/mcp@latest \
    @modelcontextprotocol/server-sequential-thinking \
    @githubnext/github-copilot-cli && \
    npx playwright install --with-deps chromium

# Install tomli for TOML parsing
RUN python3 -m pip install --no-cache-dir --break-system-packages tomli

# Create non-root user (UID 1000 for WSL2 compatibility)
RUN useradd -m -s /bin/bash -u 1000 agentuser && \
    mkdir -p /workspace /home/agentuser/.config /home/agentuser/.local/share && \
    chown -R agentuser:agentuser /workspace /home/agentuser

# Copy Playwright browsers to agentuser's home (installed as root above)
RUN mkdir -p /home/agentuser/.cache && \
    cp -r /root/.cache/ms-playwright /home/agentuser/.cache/ && \
    chown -R agentuser:agentuser /home/agentuser/.cache

USER agentuser
WORKDIR /home/agentuser

# Install pipx and uv for user
RUN python3 -m pip install --user pipx && \
    python3 -m pipx ensurepath && \
    curl -LsSf https://astral.sh/uv/install.sh | sh

ENV PATH="/home/agentuser/.local/bin:${PATH}"
ENV PATH="/home/agentuser/.cargo/bin:${PATH}"

# Pre-install Serena MCP server
RUN uvx --from "git+https://github.com/oraios/serena@main" serena --help || true

# Create config directory and copy agent configs
RUN mkdir -p /home/agentuser/.config/coding-agents
COPY --chown=agentuser:agentuser agent-configs/ /home/agentuser/.config/coding-agents/

WORKDIR /workspace
CMD ["/bin/bash"]
