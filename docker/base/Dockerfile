# Base image for containai container
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
    iptables \
    tmux \
    gosu \
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
    libseccomp-dev \
    # Capability management (for dropping caps after privileged setup)
    libcap2-bin \
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

# Install .NET workloads 
RUN dotnet workload install wasm-tools wasm-tools-net9 wasm-tools-net8 || \
    echo "⚠️  Some workloads may have failed (expected for some platforms)"; \
    rm -rf /tmp/* /root/.nuget/packages /root/.dotnet/toolResolverCache

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
COPY --chown=root:root docker/runtime/install-dotnet-preview.sh /usr/local/bin/install-dotnet-preview.sh

# Session and runtime helpers - copy all scripts in one layer
COPY --chown=root:root docker/runtime/agent-session /usr/local/bin/agent-session
COPY --chown=root:root docker/runtime/agent-session-runner /usr/local/bin/agent-session-runner
COPY --chown=root:root docker/runtime/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=root:root docker/runtime/git-credential-host-helper.sh /usr/local/bin/git-credential-host-helper.sh
COPY --chown=root:root host/utils/git-credential-proxy-server.sh /usr/local/bin/git-credential-proxy-server.sh
COPY --chown=root:root docker/runtime/gpg-host-proxy.sh /usr/local/bin/gpg-host-proxy.sh
COPY --chown=root:root host/utils/gpg-proxy-server.sh /usr/local/bin/gpg-proxy-server.sh
COPY --chown=root:root docker/runtime/setup-mcp-configs.sh /usr/local/bin/setup-mcp-configs.sh
COPY --chown=root:root docker/runtime/mcp-stub.py /usr/local/libexec/mcp-stub-core.py
COPY --chown=root:root docker/runtime/mcp-stub-runner.sh /usr/local/bin/mcp-stub-runner
COPY --chown=root:root docker/runtime/mcp-http-helper.py /usr/local/bin/mcp-http-helper.py
COPY --chown=root:root docker/runtime/capability-unseal.py /usr/local/bin/capability-unseal
COPY --chown=root:root host/utils/convert-toml-to-mcp.py /usr/local/bin/convert-toml-to-mcp.py
COPY --chown=root:root host/utils/package-agent-data.py /usr/local/bin/package-agent-data.py

# Set permissions for all scripts in one layer
RUN install -d /usr/local/libexec && \
    chmod +x \
    /usr/local/bin/install-dotnet-preview.sh \
    /usr/local/bin/agent-session \
    /usr/local/bin/agent-session-runner \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/git-credential-host-helper.sh \
    /usr/local/bin/git-credential-proxy-server.sh \
    /usr/local/bin/gpg-host-proxy.sh \
    /usr/local/bin/gpg-proxy-server.sh \
    /usr/local/bin/setup-mcp-configs.sh \
    /usr/local/bin/mcp-stub-runner \
    /usr/local/bin/mcp-http-helper.py \
    /usr/local/bin/capability-unseal \
    /usr/local/bin/convert-toml-to-mcp.py \
    /usr/local/bin/package-agent-data.py && \
    ln -sf /usr/local/bin/mcp-stub-runner /usr/local/bin/mcp-stub

# Install GitHub CLI, npm global packages, and Playwright in one layer
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/* && \
    npm install -g \
        @playwright/mcp@latest \
        @modelcontextprotocol/server-sequential-thinking \
        @githubnext/github-copilot-cli \
        @anthropic-ai/claude-code \
        @openai/codex && \
    npx playwright install --with-deps chromium && \
    npm cache clean --force && \
    rm -rf /tmp/*

# Install agentcli exec helper, task-runner daemon, and .NET components
COPY --chown=root:root artifacts/agentcli-exec /usr/local/bin/agentcli-exec
COPY --chown=root:root artifacts/agent-task-runnerd /usr/local/bin/agent-task-runnerd
COPY --chown=root:root artifacts/agent-task-sandbox /usr/local/bin/agent-task-sandbox
COPY --chown=root:root artifacts/containai-log-collector /usr/local/bin/containai-log-collector
COPY --chown=root:root artifacts/libaudit_shim.so /usr/lib/containai/libaudit_shim.so

# Set permissions for binaries, run CLI wrappers, and create users in one layer
RUN set -eux; \
    chown root:root /usr/local/bin/agentcli-exec /usr/local/bin/agent-task-runnerd /usr/local/bin/agent-task-sandbox /usr/local/bin/containai-log-collector /usr/lib/containai/libaudit_shim.so; \
    chmod 4755 /usr/local/bin/agentcli-exec; \
    chmod 0755 /usr/local/bin/agent-task-runnerd /usr/local/bin/agent-task-sandbox /usr/local/bin/containai-log-collector /usr/lib/containai/libaudit_shim.so; \
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
    fi; \
    if ! id -u agentcli >/dev/null 2>&1; then \
        useradd -m -s /usr/sbin/nologin agentcli; \
    fi; \
    usermod -a -G agentcli agentuser >/dev/null 2>&1 || true; \
    mkdir -p /workspace /home/agentuser/.config /home/agentuser/.local/share; \
    chown -R agentuser:agentuser /workspace /home/agentuser

# Snapshot mutable root dirs, prepare toolcache, and move Playwright browsers in one layer
RUN set -eux; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    snapshot_root="/opt/containai/basefs"; \
    mkdir -p "${snapshot_root}/var/lib/dpkg" \
        "${snapshot_root}/var/lib/apt" \
        "${snapshot_root}/var/cache/apt" \
        "${snapshot_root}/var/cache/debconf"; \
    cp -a /var/lib/dpkg/. "${snapshot_root}/var/lib/dpkg/"; \
    cp -a /var/lib/apt/. "${snapshot_root}/var/lib/apt/"; \
    cp -a /var/cache/apt/. "${snapshot_root}/var/cache/apt/" || true; \
    cp -a /var/cache/debconf/. "${snapshot_root}/var/cache/debconf/" || true; \
    mkdir -p /toolcache; \
    chown agentuser:agentuser /toolcache; \
    mkdir -p /home/agentuser/.cache; \
    mv /root/.cache/ms-playwright /home/agentuser/.cache/; \
    chown -R agentuser:agentuser /home/agentuser/.cache

USER agentuser
WORKDIR /home/agentuser

# Install uv for user (pipx was installed system-wide via apt)
RUN pipx --version >/dev/null && \
    curl -LsSf https://astral.sh/uv/install.sh | sh

ENV PATH="/home/agentuser/.local/bin:${PATH}"
ENV PATH="/home/agentuser/.cargo/bin:${PATH}"
ENV PATH="/toolcache/pipx/bin:${PATH}"

ENV CONTAINAI_BASEFS=/opt/containai/basefs \
    CONTAINAI_TOOLCACHE=/toolcache \
    PIP_CACHE_DIR=/toolcache/pip \
    PIPX_HOME=/toolcache/pipx \
    PIPX_BIN_DIR=/toolcache/pipx/bin \
    NPM_CONFIG_CACHE=/toolcache/npm \
    npm_config_cache=/toolcache/npm \
    YARN_CACHE_FOLDER=/toolcache/yarn \
    PNPM_HOME=/toolcache/pnpm \
    PLAYWRIGHT_BROWSERS_PATH=/toolcache/ms-playwright \
    UV_CACHE_DIR=/toolcache/uv \
    CARGO_HOME=/toolcache/cargo \
    RUSTUP_HOME=/toolcache/rustup \
    BUN_INSTALL=/toolcache/bun \
    DOTNET_CLI_HOME=/toolcache/dotnet \
    DOTNET_USER_HOME=/toolcache/dotnet \
    NUGET_PACKAGES=/toolcache/nuget/packages \
    NUGET_HTTP_CACHE_PATH=/toolcache/nuget/http-cache

USER root

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
