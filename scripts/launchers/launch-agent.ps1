# Launch a coding agent in an isolated container with its own git workspace
# The container runs persistently for VS Code Remote connection

param(
    [Parameter(Mandatory=$false)]
    [string]$Source = ".",
    
    [Parameter(Mandatory=$false)]
    [Alias("b")]
    [string]$Branch,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("copilot", "codex", "claude")]
    [string]$Agent = "copilot",
    
    [Parameter(Mandatory=$false)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [string]$DotNetPreview,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("allow-all", "restricted", "squid", "none")]
    [string]$NetworkProxy = "allow-all",
    
    [Parameter(Mandatory=$false)]
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"

# Source shared functions
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "..\utils\common-functions.ps1")

# Auto-detect WSL home directory
$WslHome = wsl bash -c 'echo $HOME' 2>$null
if (-not $WslHome) {
    Write-Host "❌ Error: Could not detect WSL home directory" -ForegroundColor Red
    Write-Host "   Make sure WSL2 is installed and running" -ForegroundColor Yellow
    exit 1
}

# Treat 'none' as alias for allow-all
if ($NetworkProxy -eq "none") {
    $NetworkProxy = "allow-all"
}

# Check Docker
if (-not (Test-DockerRunning)) {
    exit 1
}

# Determine if source is URL or local path
$IsUrl = $Source -match '^https?://'

if ($IsUrl) {
    $RepoName = [System.IO.Path]::GetFileNameWithoutExtension($Source) -replace '\.git$', ''
    $SourceType = "url"
    $GitUrl = $Source
    $OriginUrl = $GitUrl
    $WslPath = ""
} else {
    $ResolvedPath = Resolve-Path $Source -ErrorAction SilentlyContinue
    if (-not $ResolvedPath) {
        Write-Host "❌ Error: Source path does not exist: $Source" -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path (Join-Path $ResolvedPath ".git"))) {
        Write-Host "❌ Error: $Source is not a git repository" -ForegroundColor Red
        exit 1
    }
    
    $RepoName = Split-Path -Leaf $ResolvedPath
    $SourceType = "local"
    
    Push-Location $ResolvedPath
    $OriginUrl = git remote get-url origin 2>$null
    Pop-Location
    
    $WslPath = $ResolvedPath -replace '^([A-Z]):', { '/mnt/' + $_.Groups[1].Value.ToLower() } -replace '\\', '/'
    $GitUrl = ""
}

# Restricted network cannot clone URLs
if ($NetworkProxy -eq "restricted" -and $SourceType -eq "url") {
    Write-Host "❌ Restricted network mode cannot clone from a URL. Provide a local path or use -NetworkProxy allow-all." -ForegroundColor Red
    exit 1
}

# Determine branch name first
if (-not $Branch) {
    if ($SourceType -eq "local") {
        Push-Location $ResolvedPath
        $CurrentBranch = git branch --show-current 2>$null
        Pop-Location
        $Branch = if ($CurrentBranch) { $CurrentBranch } else { "main" }
    } else {
        $Branch = "main"
    }
}

# Sanitize branch name
$SafeBranch = $Branch -replace '[/\\]', '-' -replace '_', '-'
$SafeBranch = $SafeBranch.ToLower()

# Determine container names
if ($Name) {
    $ContainerName = "$Agent-$Name"
    $WorkspaceName = $Name
} else {
    $ContainerName = "$Agent-$RepoName-$SafeBranch"
    $WorkspaceName = $RepoName
}

$AgentBranch = "$Agent/$Branch"
$ProxyContainerName = "$ContainerName-proxy"
$ProxyNetworkName = "$ContainerName-net"
$ProxyImage = "coding-agents-proxy:local"

# Pull latest image
Update-AgentImage -Agent $Agent
$ImageName = "coding-agents-${Agent}:local"

# Get timezone
$TimeZone = (Get-TimeZone).Id

# Squid allowed domains
$SquidAllowedDomains = "*.github.com,*.githubcopilot.com,*.nuget.org,*.npmjs.org,*.pypi.org,*.python.org,*.microsoft.com,*.docker.io,registry-1.docker.io,api.githubcopilot.com,learn.microsoft.com,platform.uno,*.githubusercontent.com,*.azureedge.net"

# Determine network mode
$NetworkMode = "bridge"
$NetworkPolicyEnv = "allow-all"
$UseSquid = $false
$ProxyUrl = ""

switch ($NetworkProxy) {
    "restricted" {
        $NetworkMode = "none"
        $NetworkPolicyEnv = "restricted"
    }
    "squid" {
        $NetworkMode = $ProxyNetworkName
        $NetworkPolicyEnv = "squid"
        $UseSquid = $true
        $ProxyUrl = "http://${ProxyContainerName}:3128"
    }
    default {
        $NetworkPolicyEnv = "allow-all"
    }
}

Write-Host "🚀 Launching Coding Agent..." -ForegroundColor Cyan
Write-Host "🎯 Agent: $Agent" -ForegroundColor White
Write-Host "📁 Source: $Source ($SourceType)" -ForegroundColor White
Write-Host "🌿 Branch: $AgentBranch" -ForegroundColor White
Write-Host "🏷️  Container: $ContainerName" -ForegroundColor White
Write-Host "🐳 Image: $ImageName" -ForegroundColor White
Write-Host "🌐 Network policy: $NetworkPolicyEnv" -ForegroundColor White
Write-Host ""

# Check if container already exists
if (Test-ContainerExists $ContainerName) {
    Write-Host "📦 Container '$ContainerName' already exists" -ForegroundColor Yellow
    $State = Get-ContainerStatus $ContainerName
    
    # Handle existing proxy if squid mode
    if ($UseSquid) {
        $ExistingProxy = docker inspect -f '{{ index .Config.Labels "coding-agents.proxy-container" }}' $ContainerName 2>$null
        $ExistingNetwork = docker inspect -f '{{ index .Config.Labels "coding-agents.proxy-network" }}' $ContainerName 2>$null
        if ($ExistingProxy) { $ProxyContainerName = $ExistingProxy }
        if ($ExistingNetwork) { $ProxyNetworkName = $ExistingNetwork }
        Ensure-SquidProxy -NetworkName $ProxyNetworkName -ProxyContainer $ProxyContainerName -ProxyImage $ProxyImage -AgentContainer $ContainerName -SquidAllowedDomains $SquidAllowedDomains
    }
    
    if ($State -eq "running") {
        Write-Host "✅ Container is already running" -ForegroundColor Green
        Write-Host "   Connect via: docker exec -it $ContainerName bash" -ForegroundColor Gray
        Write-Host "   Or use VS Code Dev Containers extension" -ForegroundColor Gray
        exit 0
    } else {
        Write-Host "▶️  Starting existing container..." -ForegroundColor Cyan
        docker start $ContainerName | Out-Null
        Write-Host "✅ Container started" -ForegroundColor Green
        exit 0
    }
}

# Setup squid proxy if needed
if ($UseSquid) {
    Ensure-SquidProxy -NetworkName $ProxyNetworkName -ProxyContainer $ProxyContainerName -ProxyImage $ProxyImage -AgentContainer $ContainerName -SquidAllowedDomains $SquidAllowedDomains
}

# Build docker arguments
$autoPushValue = if ($NoPush) { "false" } else { "true" }

$dockerArgs = @(
    "run", "-d",
    "--name", $ContainerName,
    "--hostname", $ContainerName,
    "-e", "TZ=$TimeZone",
    "-e", "SOURCE_TYPE=$SourceType",
    "-e", "REPO_NAME=$WorkspaceName",
    "-e", "AGENT_BRANCH=$AgentBranch",
    "-e", "NETWORK_POLICY=$NetworkPolicyEnv",
    "-e", "AUTO_PUSH_ON_SHUTDOWN=$autoPushValue",
    "--label", "coding-agents.type=agent",
    "--label", "coding-agents.agent=$Agent",
    "--label", "coding-agents.repo=$RepoName",
    "--label", "coding-agents.branch=$Branch",
    "--label", "coding-agents.network-policy=$NetworkPolicyEnv",
    "-v", "${WslHome}/.gitconfig:/home/agentuser/.gitconfig:ro",
    "-v", "${WslHome}/.config/gh:/home/agentuser/.config/gh:ro",
    "-v", "${WslHome}/.config/github-copilot:/home/agentuser/.config/github-copilot:ro"
)

# Add source-specific vars
if ($SourceType -eq "url") {
    $dockerArgs += "-e", "GIT_URL=$GitUrl"
} else {
    $dockerArgs += "-e", "LOCAL_REPO_PATH=$WslPath"
    $dockerArgs += "-v", "${WslPath}:/tmp/source-repo:ro"
}

if ($OriginUrl) { $dockerArgs += "-e", "ORIGIN_URL=$OriginUrl" }
if ($DotNetPreview) { $dockerArgs += "-e", "DOTNET_PREVIEW_CHANNEL=$DotNetPreview" }

# Add proxy environment if squid
if ($UseSquid) {
    $dockerArgs += "-e", "HTTP_PROXY=$ProxyUrl"
    $dockerArgs += "-e", "HTTPS_PROXY=$ProxyUrl"
    $dockerArgs += "-e", "http_proxy=$ProxyUrl"
    $dockerArgs += "-e", "https_proxy=$ProxyUrl"
    $dockerArgs += "-e", "NO_PROXY=localhost,127.0.0.1,.internal,::1"
    $dockerArgs += "-e", "no_proxy=localhost,127.0.0.1,.internal,::1"
    $dockerArgs += "--label", "coding-agents.proxy-container=$ProxyContainerName"
    $dockerArgs += "--label", "coding-agents.proxy-network=$ProxyNetworkName"
    $dockerArgs += "--label", "coding-agents.proxy-image=$ProxyImage"
}

# Add optional agent configs
if (Test-Path "${WslHome}/.config/codex") { $dockerArgs += "-v", "${WslHome}/.config/codex:/home/agentuser/.config/codex:ro" }
if (Test-Path "${WslHome}/.config/claude") { $dockerArgs += "-v", "${WslHome}/.config/claude:/home/agentuser/.config/claude:ro" }
if (Test-Path "${WslHome}/.config/coding-agents/mcp-secrets.env") { $dockerArgs += "-v", "${WslHome}/.config/coding-agents/mcp-secrets.env:/home/agentuser/.mcp-secrets.env:ro" }

# Final args
$dockerArgs += "-w", "/workspace"
$dockerArgs += "--network", $NetworkMode
$dockerArgs += "--security-opt", "no-new-privileges:true"
$dockerArgs += "--cpus=4"
$dockerArgs += "--memory=8g"
$dockerArgs += $ImageName
$dockerArgs += "sleep", "infinity"

# Create container
Write-Host "📦 Creating container..." -ForegroundColor Cyan
try {
    $ContainerId = docker @dockerArgs
} catch {
    Write-Host "❌ Failed to create container" -ForegroundColor Red
    if ($UseSquid) {
        docker rm -f $ProxyContainerName 2>$null | Out-Null
        docker network rm $ProxyNetworkName 2>$null | Out-Null
    }
    exit 1
}

# Setup repository inside container
Write-Host "📥 Setting up repository..." -ForegroundColor Cyan
$setupScript = New-RepoSetupScript

try {
    $setupScript | docker exec -i $ContainerName bash
} catch {
    Write-Host "❌ Failed to setup repository" -ForegroundColor Red
    docker rm -f $ContainerName | Out-Null
    exit 1
}

Write-Host ""
Write-Host "✅ Container '$ContainerName' is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "Connect via:" -ForegroundColor Cyan
Write-Host "  • VS Code: Attach to running container '$ContainerName'" -ForegroundColor White
Write-Host "  • Terminal: docker exec -it $ContainerName bash" -ForegroundColor White
Write-Host ""
Write-Host "Repository: /workspace" -ForegroundColor Gray
Write-Host "Branch: $AgentBranch" -ForegroundColor Gray
