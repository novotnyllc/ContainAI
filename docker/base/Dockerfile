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
    socat \
    tmux \
    # Build tools (REQUIRED for development)
    build-essential \
    # Python with dev headers (for building native extensions)
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    python3-tomli \
    pipx \
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
    libasound2t64 \
    libatspi2.0-0 \
    libxshmfence1 \
    # .NET runtime dependencies
    libc6 \
    libgcc-s1 \
    libgssapi-krb5-2 \
    libicu74 \
    libssl3t64 \
    libstdc++6 \
    libunwind8 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x (required for MCP servers and building Node projects)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install .NET SDKs (agents need SDK, not just runtime, to build C# projects)
RUN dotnet_install_url="https://dot.net/v1/dotnet-install.sh" && \
    dotnet_install_script="dotnet-install.sh" && \
    rm -f "$dotnet_install_script" && \
    for attempt in 1 2 3 4 5; do \
        if curl -fsSL "$dotnet_install_url" -o "$dotnet_install_script"; then \
            chmod +x "$dotnet_install_script" && \
            break; \
        fi; \
        echo "dotnet install script download failed (attempt ${attempt})" >&2; \
        sleep $((attempt * 2)); \
    done && \
    if [ ! -s "$dotnet_install_script" ]; then \
        echo "dotnet install script download failed after retries" >&2; \
        exit 1; \
    fi && \
    for channel in 8.0 9.0 10.0; do \
        install_success=0; \
        for attempt in 1 2 3; do \
            if ./"$dotnet_install_script" --channel "$channel" --install-dir /usr/share/dotnet; then \
                install_success=1; \
                break; \
            fi; \
            echo "dotnet install for channel ${channel} failed (attempt ${attempt})" >&2; \
            sleep $((attempt * 2)); \
        done; \
        if [ "$install_success" -ne 1 ]; then \
            echo "dotnet install failed after retries for channel ${channel}" >&2; \
            exit 1; \
        fi; \
    done && \
    rm "$dotnet_install_script" && \
    rm -f /usr/bin/dotnet && \
    ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH="${PATH}:/usr/share/dotnet"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=true
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=true

# Install .NET workloads (MAUI, Blazor, WASM, etc.)
RUN dotnet workload install wasm-tools wasm-tools-net9 wasm-tools-net8 ios android maccatalyst tvos || \
    echo "⚠️  Some workloads may have failed (expected for some platforms)"

# Install PowerShell using the universal package guidance (falls back to tarball on ARM)
ARG POWERSHELL_VERSION="7.4.13"
ARG POWERSHELL_RELEASE_TAG="v7.4.13"
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

# Copy .NET preview installer script
COPY --chown=root:root scripts/runtime/install-dotnet-preview.sh /usr/local/bin/install-dotnet-preview.sh
RUN chmod +x /usr/local/bin/install-dotnet-preview.sh

# Session and runtime helpers
COPY --chown=root:root scripts/runtime/agent-session /usr/local/bin/agent-session
COPY --chown=root:root scripts/runtime/agent-session-runner /usr/local/bin/agent-session-runner
COPY --chown=root:root scripts/runtime/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=root:root scripts/runtime/git-credential-host-helper.sh /usr/local/bin/git-credential-host-helper.sh
COPY --chown=root:root scripts/runtime/git-credential-proxy-server.sh /usr/local/bin/git-credential-proxy-server.sh
COPY --chown=root:root scripts/runtime/gpg-host-proxy.sh /usr/local/bin/gpg-host-proxy.sh
COPY --chown=root:root scripts/runtime/gpg-proxy-server.sh /usr/local/bin/gpg-proxy-server.sh
COPY --chown=root:root scripts/runtime/setup-mcp-configs.sh /usr/local/bin/setup-mcp-configs.sh
COPY --chown=root:root scripts/utils/convert-toml-to-mcp.py /usr/local/bin/convert-toml-to-mcp.py
RUN chmod +x \
    /usr/local/bin/agent-session \
    /usr/local/bin/agent-session-runner \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/git-credential-host-helper.sh \
    /usr/local/bin/git-credential-proxy-server.sh \
    /usr/local/bin/gpg-host-proxy.sh \
    /usr/local/bin/gpg-proxy-server.sh \
    /usr/local/bin/setup-mcp-configs.sh \
    /usr/local/bin/convert-toml-to-mcp.py

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

# Create non-root user (reuse Ubuntu's default UID 1000 user if present)
RUN set -eux; \
    if id -u agentuser >/dev/null 2>&1; then \
        true; \
    elif id -u ubuntu >/dev/null 2>&1; then \
        usermod -l agentuser -d /home/agentuser -m ubuntu; \
        if getent group ubuntu >/dev/null 2>&1; then \
            groupmod -n agentuser ubuntu; \
        fi; \
        usermod -s /bin/bash agentuser; \
    else \
        useradd -m -s /bin/bash -u 1000 agentuser; \
    fi && \
    mkdir -p /workspace /home/agentuser/.config /home/agentuser/.local/share && \
    chown -R agentuser:agentuser /workspace /home/agentuser

# Copy Playwright browsers to agentuser's home (installed as root above)
RUN mkdir -p /home/agentuser/.cache && \
    cp -r /root/.cache/ms-playwright /home/agentuser/.cache/ && \
    chown -R agentuser:agentuser /home/agentuser/.cache

USER agentuser
WORKDIR /home/agentuser

# Install uv for user (pipx was installed system-wide via apt)
RUN pipx --version >/dev/null && \
    curl -LsSf https://astral.sh/uv/install.sh | sh

ENV PATH="/home/agentuser/.local/bin:${PATH}"
ENV PATH="/home/agentuser/.cargo/bin:${PATH}"

# Pre-install Serena MCP server
RUN uvx --from "git+https://github.com/oraios/serena@main" serena --help || true

USER root

USER agentuser

WORKDIR /workspace
CMD ["/bin/bash"]
