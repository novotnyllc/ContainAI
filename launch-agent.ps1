# Launch a coding agent in an isolated container with its own git workspace
# The container runs persistently for VS Code Remote connection

param(
    [Parameter(Mandatory=$false)]
    [string]$Source = ".",
    
    [Parameter(Mandatory=$false)]
    [Alias("b")]
    [string]$Branch,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("copilot", "codex", "claude", "all")]
    [string]$Agent = "all",
    
    [Parameter(Mandatory=$false)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [string]$DotNetPreview,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("allow-all", "restricted", "squid", "none")]
    [string]$NetworkProxy = "allow-all"
)

$ErrorActionPreference = "Stop"

function Ensure-SquidProxy {
    param(
        [string]$NetworkName,
        [string]$ProxyContainer,
        [string]$ProxyImage,
        [switch]$Recreate
    )

    $existingNetwork = docker network ls --filter "name=^${NetworkName}$" --format "{{.Name}}" 2>$null
    if (-not $existingNetwork) {
        docker network create $NetworkName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create docker network '$NetworkName'"
        }
        Set-Variable -Scope Script -Name CreatedNetwork -Value $true
    }

    if ($Recreate -and (docker ps -a --filter "name=^${ProxyContainer}$" --format "{{.Names}}" 2>$null)) {
        docker rm -f $ProxyContainer > $null 2>&1
    }

    $existingProxy = docker ps -a --filter "name=^${ProxyContainer}$" --format "{{.Names}}" 2>$null
    if ($existingProxy) {
        $state = docker inspect -f '{{.State.Status}}' $ProxyContainer 2>$null
        if ($state -ne "running") {
            docker start $ProxyContainer | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to start proxy container '$ProxyContainer'"
            }
        }
    } else {
        docker run -d `
            --name $ProxyContainer `
            --hostname $ProxyContainer `
            --network $NetworkName `
            --restart unless-stopped `
            --label "coding-agents.proxy-of=$ContainerName" `
            --label "coding-agents.proxy-image=$ProxyImage" `
            $ProxyImage | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to launch proxy container '$ProxyContainer'"
        }

        Set-Variable -Scope Script -Name CreatedProxy -Value $true
    }
}

$script:CreatedNetwork = $false
$script:CreatedProxy = $false

# Auto-detect WSL home directory
$WslHome = wsl bash -c 'echo $HOME' 2>$null
if (-not $WslHome) {
    Write-Host "❌ Error: Could not detect WSL home directory" -ForegroundColor Red
    Write-Host "   Make sure WSL2 is installed and running" -ForegroundColor Yellow
    exit 1
}

# Get timezone from host
$TimeZone = (Get-TimeZone).Id

# Treat 'none' as alias for allow-all for backwards compatibility
if ($NetworkProxy -eq "none") {
    $NetworkProxy = "allow-all"
}

# Determine if source is a URL or local path
$IsUrl = $Source -match '^https?://'
$IsGitUrl = $Source -match '\.git$' -or $IsUrl

if ($IsUrl) {
    # Extract repo name from URL
    $RepoName = [System.IO.Path]::GetFileNameWithoutExtension($Source)
    $RepoName = $RepoName -replace '\.git$', ''
    $SourceType = "url"
    $GitUrl = $Source
} else {
    # Local path - resolve it
    $ResolvedPath = Resolve-Path $Source -ErrorAction SilentlyContinue
    if (-not $ResolvedPath) {
        Write-Host "❌ Error: Source path does not exist: $Source" -ForegroundColor Red
        exit 1
    }
    
    # Check if it's a git repository
    $IsGitRepo = Test-Path (Join-Path $ResolvedPath ".git")
    if (-not $IsGitRepo) {
        Write-Host "❌ Error: $Source is not a git repository" -ForegroundColor Red
        exit 1
    }
    
    $RepoName = Split-Path -Leaf $ResolvedPath
    $SourceType = "local"
    
    # Get the git remote URL if it exists
    Push-Location $ResolvedPath
    $GitUrl = git remote get-url origin 2>$null
    Pop-Location
    
    # Convert Windows path to WSL path
    $WslPath = $ResolvedPath -replace '^([A-Z]):', { '/mnt/' + $_.Groups[1].Value.ToLower() } -replace '\\', '/'
}

if ($NetworkProxy -eq "restricted" -and $SourceType -eq "url") {
    Write-Host "❌ Restricted network mode cannot clone from a URL. Provide a local path or use -NetworkProxy allow-all." -ForegroundColor Red
    exit 1
}

# Determine container and workspace names
if ($Name) {
    $ContainerName = "$Agent-$Name"
    $WorkspaceName = $Name
} else {
    $ContainerName = "$Agent-$RepoName"
    $WorkspaceName = $RepoName
}

# Determine branch name
if (-not $Branch) {
    if ($SourceType -eq "local") {
        Push-Location $ResolvedPath
        $CurrentBranch = git branch --show-current 2>$null
        Pop-Location
        if ($CurrentBranch) {
            $Branch = $CurrentBranch
        } else {
            $Branch = "main"
        }
    } else {
        $Branch = "main"
    }
}

$AgentBranch = "$Agent/$Branch"

# Select image based on agent parameter
$ImageName = switch ($Agent) {
    "copilot" { "coding-agents-copilot:local" }
    "codex" { "coding-agents-codex:local" }
    "claude" { "coding-agents-claude:local" }
    default { "coding-agents:local" }
}

$ProxyImage = "coding-agents-proxy:local"
$ProxyContainerName = "$ContainerName-proxy"
$ProxyNetworkName = "$ContainerName-net"
$ProxyUrl = $null
$UseSquid = $false

$NetworkMode = "bridge"
$NetworkPolicyEnv = "allow-all"

switch ($NetworkProxy) {
    "restricted" {
        $NetworkMode = "none"
        $NetworkPolicyEnv = "restricted"
    }
    "squid" {
        $NetworkMode = $ProxyNetworkName
        $NetworkPolicyEnv = "squid"
        $UseSquid = $true
    }
    Default {
        $NetworkPolicyEnv = "allow-all"
    }
}

$NetworkSummary = switch ($NetworkPolicyEnv) {
    "restricted" { "no outbound network" }
    "squid" { "proxied via Squid sidecar" }
    Default { "standard Docker bridge" }
}

Write-Host "🚀 Launching Coding Agent..." -ForegroundColor Cyan
Write-Host "🎯 Agent: $Agent" -ForegroundColor Cyan
Write-Host "📁 Source: $Source ($SourceType)" -ForegroundColor Cyan
Write-Host "🌿 Branch: $AgentBranch" -ForegroundColor Cyan
Write-Host "🏷️  Container: $ContainerName" -ForegroundColor Cyan
Write-Host "🐳 Image: $ImageName" -ForegroundColor Cyan
Write-Host "🌐 Network policy: $NetworkPolicyEnv (docker --network $NetworkMode → $NetworkSummary)" -ForegroundColor Cyan
Write-Host ""

# Check if container already exists
$ExistingContainer = docker ps -a --filter "name=^${ContainerName}$" --format "{{.Names}}" 2>$null
if ($ExistingContainer) {
    Write-Host "📦 Container '$ContainerName' already exists" -ForegroundColor Yellow
    $State = docker inspect -f '{{.State.Status}}' $ContainerName
    $ExistingPolicy = docker inspect -f '{{ index .Config.Labels "coding-agents.network-policy" }}' $ContainerName 2>$null

    if ($ExistingPolicy -eq "squid") {
        $ExistingProxyName = docker inspect -f '{{ index .Config.Labels "coding-agents.proxy-container" }}' $ContainerName 2>$null
        if (-not $ExistingProxyName) { $ExistingProxyName = "$ContainerName-proxy" }
        $ExistingNetworkName = docker inspect -f '{{ index .Config.Labels "coding-agents.proxy-network" }}' $ContainerName 2>$null
        if (-not $ExistingNetworkName) { $ExistingNetworkName = "$ContainerName-net" }

        $ProxyExists = docker ps -a --filter "name=^${ExistingProxyName}$" --format "{{.Names}}" 2>$null
        $ProxyImageForExisting = docker inspect -f '{{ index .Config.Labels "coding-agents.proxy-image" }}' $ExistingProxyName 2>$null
        if (-not $ProxyImageForExisting) { $ProxyImageForExisting = $ProxyImage }

        if (-not $ProxyExists -and -not (docker image inspect $ProxyImageForExisting > $null 2>&1)) {
            Write-Host "⚠️  Squid proxy image '$ProxyImageForExisting' not available. Run ./scripts/build.sh to rebuild images before restarting." -ForegroundColor Yellow
        } else {
            try {
                Ensure-SquidProxy -NetworkName $ExistingNetworkName -ProxyContainer $ExistingProxyName -ProxyImage $ProxyImageForExisting
            } catch {
                Write-Host "⚠️  Failed to ensure Squid proxy: $_" -ForegroundColor Yellow
            }
        }
    }
    
    if ($State -eq "running") {
        Write-Host "✅ Container is running" -ForegroundColor Green
        Write-Host ""
        Write-Host "To connect with VS Code:" -ForegroundColor Cyan
        Write-Host "  1. Install 'Remote - SSH' extension" -ForegroundColor White
        Write-Host "  2. Run: docker exec -it $ContainerName bash" -ForegroundColor White
        Write-Host "Or attach directly with 'Docker' extension" -ForegroundColor White
        exit 0
    } else {
        Write-Host "▶️  Starting existing container..." -ForegroundColor Yellow
        docker start -ai $ContainerName
        exit $LASTEXITCODE
    }
}

if ($UseSquid -and -not $ExistingContainer) {
    if (-not (docker image inspect $ProxyImage > $null 2>&1)) {
        Write-Host "❌ Proxy image '$ProxyImage' not found. Run ./scripts/build.sh to build the proxy image." -ForegroundColor Red
        exit 1
    }

    try {
        Ensure-SquidProxy -NetworkName $ProxyNetworkName -ProxyContainer $ProxyContainerName -ProxyImage $ProxyImage -Recreate
        $ProxyUrl = "http://${ProxyContainerName}:3128"
    } catch {
        Write-Host "❌ Failed to initialize Squid proxy: $_" -ForegroundColor Red
        if ($script:CreatedProxy) { docker rm -f $ProxyContainerName > $null 2>&1 }
        if ($script:CreatedNetwork) { docker network rm $ProxyNetworkName > $null 2>&1 }
        exit 1
    }
}

# Build docker arguments
$dockerArgs = @(
    "run", "-d",
    "--name", $ContainerName,
    "--hostname", $ContainerName,
    "-e", "TZ=$TimeZone",
    "-e", "SOURCE_TYPE=$SourceType",
    "-e", "REPO_NAME=$WorkspaceName",
    "-e", "AGENT_BRANCH=$AgentBranch",
    "-e", "NETWORK_POLICY=$NetworkPolicyEnv",
    "--label", "coding-agents.network-policy=$NetworkPolicyEnv",
    "-v", "${WslHome}/.gitconfig:/home/agentuser/.gitconfig:ro",
    "-v", "${WslHome}/.config/gh:/home/agentuser/.config/gh:ro",
    "-v", "${WslHome}/.config/github-copilot:/home/agentuser/.config/github-copilot:ro"
)

# Add source-specific environment variables
if ($SourceType -eq "url") {
    $dockerArgs += "-e"
    $dockerArgs += "GIT_URL=$GitUrl"
} else {
    $dockerArgs += "-e"
    $dockerArgs += "LOCAL_REPO_PATH=$WslPath"
    # Mount the local repo as a temporary source (read-only)
    $dockerArgs += "-v"
    $dockerArgs += "${WslPath}:/tmp/source-repo:ro"
}

if ($GitUrl) {
    $dockerArgs += "-e"
    $dockerArgs += "ORIGIN_URL=$GitUrl"
}

# Add .NET preview channel if specified
if ($DotNetPreview) {
    $dockerArgs += "-e"
    $dockerArgs += "DOTNET_PREVIEW_CHANNEL=$DotNetPreview"
}

if ($UseSquid -and $ProxyUrl) {
    $dockerArgs += "-e"
    $dockerArgs += "HTTP_PROXY=$ProxyUrl"
    $dockerArgs += "-e"
    $dockerArgs += "HTTPS_PROXY=$ProxyUrl"
    $dockerArgs += "-e"
    $dockerArgs += "http_proxy=$ProxyUrl"
    $dockerArgs += "-e"
    $dockerArgs += "https_proxy=$ProxyUrl"
    $dockerArgs += "-e"
    $dockerArgs += "NO_PROXY=localhost,127.0.0.1,.internal,::1"
    $dockerArgs += "-e"
    $dockerArgs += "no_proxy=localhost,127.0.0.1,.internal,::1"

    $dockerArgs += "--label"
    $dockerArgs += "coding-agents.proxy-container=$ProxyContainerName"
    $dockerArgs += "--label"
    $dockerArgs += "coding-agents.proxy-network=$ProxyNetworkName"
    $dockerArgs += "--label"
    $dockerArgs += "coding-agents.proxy-image=$ProxyImage"
}

# Add optional agent configs if they exist
if (wsl test -d "${WslHome}/.config/codex") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/codex:/home/agentuser/.config/codex:ro"
}
if (wsl test -d "${WslHome}/.config/claude") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/claude:/home/agentuser/.config/claude:ro"
}

# Add MCP secrets if they exist
if (wsl test -f "${WslHome}/.config/coding-agents/mcp-secrets.env") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/coding-agents/mcp-secrets.env:/home/agentuser/.mcp-secrets.env:ro"
}

$dockerArgs += @(
    "-w", "/workspace",
    "--network", $NetworkMode,
    "--security-opt", "no-new-privileges:true",
    "--cpus=4",
    "--memory=8g",
    $ImageName,
    "sleep", "infinity"
)

# Create and start the container
Write-Host "📦 Creating container..." -ForegroundColor Cyan
$ContainerId = & docker $dockerArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create container" -ForegroundColor Red
    if ($UseSquid) {
        if ($script:CreatedProxy) { docker rm -f $ProxyContainerName > $null 2>&1 }
        if ($script:CreatedNetwork) { docker network rm $ProxyNetworkName > $null 2>&1 }
    }
    exit 1
}

Write-Host "✅ Container created: $ContainerId" -ForegroundColor Green
Write-Host ""

# Setup the repository inside the container
Write-Host "📥 Setting up repository..." -ForegroundColor Cyan

$setupScript = @"
#!/bin/bash
set -e

TARGET_DIR="/workspace"
mkdir -p "\$TARGET_DIR"

# Clean target directory to ensure a fresh workspace
if [ -d "\$TARGET_DIR" ] && [ "\$(find "\$TARGET_DIR" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    find "\$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

if [ "\$SOURCE_TYPE" = "url" ]; then
    echo "🌐 Cloning repository from \$GIT_URL..."
    git clone "\$GIT_URL" "\$TARGET_DIR"
    echo "✅ Repository cloned"
else
    echo "📋 Copying repository from host..."
    cp -a /tmp/source-repo/. "\$TARGET_DIR/"
    echo "✅ Repository copied"
fi

cd "\$TARGET_DIR"

# Setup dual remotes
if [ -n "\$ORIGIN_URL" ]; then
    echo "🔗 Setting up remotes..."
    
    # Ensure origin is set correctly
    if git remote get-url origin 2>/dev/null; then
        git remote set-url origin "\$ORIGIN_URL"
    else
        git remote add origin "\$ORIGIN_URL"
    fi
    
    # Add local remote pointing to the host repository
    if [ "\$SOURCE_TYPE" = "local" ]; then
        git remote add local "\$LOCAL_REPO_PATH" 2>/dev/null || git remote set-url local "\$LOCAL_REPO_PATH"
        echo "  • origin: \$ORIGIN_URL"
        echo "  • local: \$LOCAL_REPO_PATH (default push)"
        
        # Set local as default push remote
        git config remote.pushDefault local
    else
        echo "  • origin: \$ORIGIN_URL"
    fi
else
    echo "ℹ️  No origin remote configured"
fi

# Create and checkout agent branch
echo "🌿 Creating branch: \$AGENT_BRANCH"
git checkout -b "\$AGENT_BRANCH" 2>/dev/null || git checkout "\$AGENT_BRANCH"

echo "✅ Repository setup complete"
echo ""
echo "Branch: \$(git branch --show-current)"
echo "Remotes:"
git remote -v | head -4

# Configure git to use HTTPS with gh credential helper
git config --global credential.helper ""
git config --global credential.helper '!gh auth git-credential'

# Setup MCP if config exists
if [ -f "/workspace/config.toml" ]; then
    echo ""
    echo "⚙️  Setting up MCP configurations..."
    /usr/local/bin/setup-mcp-configs.sh
fi

# Load MCP secrets if available
if [ -f "/home/agentuser/.mcp-secrets.env" ]; then
    echo "🔐 MCP secrets available"
fi

# Install .NET preview SDK if requested
if [ -n "$DOTNET_PREVIEW_CHANNEL" ]; then
    echo ""
    echo "📦 Installing .NET SDK $DOTNET_PREVIEW_CHANNEL preview..."
    /usr/local/bin/install-dotnet-preview.sh "$DOTNET_PREVIEW_CHANNEL" || echo "⚠️  Preview installation failed (may not exist yet)"
fi

echo ""
echo "✨ Workspace ready at /workspace"
"@

$setupScript | docker exec -i $ContainerName bash

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to setup repository" -ForegroundColor Red
    Write-Host "Cleaning up container..." -ForegroundColor Yellow
    docker rm -f $ContainerName | Out-Null
    if ($UseSquid) {
        docker rm -f $ProxyContainerName > $null 2>&1
        docker network rm $ProxyNetworkName > $null 2>&1
    }
    exit 1
}

Write-Host ""
Write-Host "✅ Agent is running!" -ForegroundColor Green
Write-Host ""
Write-Host "To connect with VS Code:" -ForegroundColor Cyan
Write-Host "  1. Install 'Dev Containers' extension" -ForegroundColor White
Write-Host "  2. Click the remote button (bottom-left)" -ForegroundColor White
Write-Host "  3. Select 'Attach to Running Container'" -ForegroundColor White
Write-Host "  4. Choose '$ContainerName'" -ForegroundColor White
Write-Host ""
Write-Host "Or connect via shell:" -ForegroundColor Cyan
Write-Host "  docker exec -it $ContainerName bash" -ForegroundColor White
Write-Host ""
Write-Host "To stop:" -ForegroundColor Cyan
Write-Host "  docker stop $ContainerName" -ForegroundColor White
if ($UseSquid) {
    Write-Host "  docker stop $ProxyContainerName  # Squid proxy" -ForegroundColor White
}
Write-Host ""
Write-Host "To remove:" -ForegroundColor Cyan
Write-Host "  docker rm -f $ContainerName" -ForegroundColor White
if ($UseSquid) {
    Write-Host "  docker rm -f $ProxyContainerName  # Squid proxy" -ForegroundColor White
    Write-Host "  docker network rm $ProxyNetworkName  # Shared proxy network" -ForegroundColor White
}
