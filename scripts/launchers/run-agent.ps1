# Launch an ephemeral coding agent session that auto-attaches to the agent CLI
# Containers auto-clean on exit but keep git safeguards and host integrations

param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("copilot", "codex", "claude")]
    [string]$Agent,
    
    [Parameter(Mandatory=$false, Position=1)]
    [string]$Source = ".",
    
    [Parameter(Mandatory=$false)]
    [Alias("b")]
    [string]$Branch,
    
    [Parameter(Mandatory=$false)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [string]$DotNetPreview,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("allow-all", "restricted", "squid", "none")]
    [string]$NetworkProxy = "allow-all",
    
    [Parameter(Mandatory=$false)]
    [string]$Cpu = "4",
    
    [Parameter(Mandatory=$false)]
    [string]$Memory = "8g",
    
    [Parameter(Mandatory=$false)]
    [string]$Gpu,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoPush,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseCurrentBranch,
    
    [Parameter(Mandatory=$false)]
    [Alias("y")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$BranchFromFlag = $PSBoundParameters.ContainsKey('Branch')
$LocalRemoteHostPath = ""
$LocalRemoteWslPath = ""
$LocalRemoteUrl = ""
$LocalRepoPathValue = ""

# Source shared functions
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "..\utils\common-functions.ps1")

$RepoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
Invoke-LauncherUpdateCheck -RepoRoot $RepoRoot -Context "run-agent"

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

$ContainerCli = Get-ContainerCli
if (-not $ContainerCli) {
    Write-Host "❌ Error: Unable to determine container runtime" -ForegroundColor Red
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
    $LocalRepoPathValue = $WslPath
    if (-not $NoPush) {
        $LocalRemoteDir = [Environment]::GetEnvironmentVariable("CODING_AGENTS_LOCAL_REMOTES_DIR")
        if ([string]::IsNullOrWhiteSpace($LocalRemoteDir)) {
            $LocalRemoteDir = Join-Path $env:USERPROFILE ".coding-agents\\local-remotes"
        }
        if (-not (Test-Path $LocalRemoteDir)) {
            New-Item -ItemType Directory -Path $LocalRemoteDir -Force | Out-Null
        }
        $RepoHash = Get-RepoPathHash -Path $ResolvedPath
        $LocalRemoteHostPath = Join-Path $LocalRemoteDir ("{0}.git" -f $RepoHash)
        if (-not (Test-Path $LocalRemoteHostPath)) {
            git init --bare "$LocalRemoteHostPath" 2>$null | Out-Null
        }
        $LocalRemoteWslPath = $LocalRemoteHostPath -replace '^([A-Z]):', { '/mnt/' + $_.Groups[1].Value.ToLower() } -replace '\\', '/'
        $LocalRemoteUrl = "file:///tmp/local-remote"
        $LocalRepoPathValue = $LocalRemoteUrl
    }

    if (-not $NoPush -and [string]::IsNullOrWhiteSpace($LocalRemoteUrl)) {
        throw "Failed to configure secure local remote for auto-push"
    }
}

if ($UseCurrentBranch) {
    if ($SourceType -ne "local") {
        Write-Host "❌ Error: -UseCurrentBranch is only supported for local repositories" -ForegroundColor Red
        exit 1
    }
    if ($BranchFromFlag) {
        Write-Host "❌ Error: -UseCurrentBranch cannot be combined with -Branch" -ForegroundColor Red
        exit 1
    }
}

# Restricted network cannot clone URLs
if ($NetworkProxy -eq "restricted" -and $SourceType -eq "url") {
    Write-Host "❌ Restricted network mode cannot clone from a URL. Provide a local path or use -NetworkProxy allow-all." -ForegroundColor Red
    exit 1
}

# Helper: Check if branch name follows agent naming convention
function Test-AgentBranch {
    param([string]$BranchName)
    return $BranchName -match '^(copilot|codex|claude)/'
}

function Get-RepoPathHash {
    param([string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Path)
        $hash = $sha.ComputeHash($bytes)
        $hex = -join ($hash | ForEach-Object { $_.ToString("x2") })
        return $hex.Substring(0,16)
    }
    finally {
        $sha.Dispose()
    }
}

# Helper: Find next available session number
function Find-NextSession {
    param(
        [string]$RepoPath,
        [string]$Agent
    )
    Push-Location $RepoPath
    $n = 1
    while ($true) {
        git show-ref --verify --quiet "refs/heads/$Agent/session-$n" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            break
        }
        $n++
    }
    Pop-Location
    return $n
}

# Determine branch name with safety checks
if (-not $Branch) {
    if ($SourceType -eq "local") {
        Push-Location $ResolvedPath
        $CurrentBranch = git branch --show-current 2>$null
        Pop-Location
        
        # Safety: Never use current branch unless it's an agent branch or explicitly allowed
        if ($UseCurrentBranch) {
            if (-not $CurrentBranch) {
                Write-Host "❌ Error: Repository is in a detached HEAD state; cannot use -UseCurrentBranch" -ForegroundColor Red
                exit 1
            }
            $Branch = $CurrentBranch
            Write-Host "⚠️  Warning: Using current branch directly (-UseCurrentBranch specified)" -ForegroundColor Yellow
        } elseif (Test-AgentBranch $CurrentBranch) {
            # Current branch is already an agent branch, safe to use
            $Branch = $CurrentBranch
            Write-Host "✓ Current branch '$CurrentBranch' is an agent branch" -ForegroundColor Green
        } else {
            # Generate unique session branch
            $SessionNum = Find-NextSession -RepoPath $ResolvedPath -Agent $Agent
            $Branch = "session-$SessionNum"
            $CurrentDisplay = if ($CurrentBranch) { $CurrentBranch } else { "main" }
            Write-Host "ℹ️  Creating new branch '$Agent/$Branch' (current: $CurrentDisplay)" -ForegroundColor Cyan
        }
    } else {
        $Branch = "main"
    }
}

# Validate branch name
if (-not (Test-ValidBranchName $Branch)) {
    Write-Host "❌ Error: Invalid branch name: $Branch" -ForegroundColor Red
    Write-Host "   Branch names must start with alphanumeric and contain only: a-z, A-Z, 0-9, /, _, ., -" -ForegroundColor Yellow
    exit 1
}

# For local repos, handle agent branch conflicts when creating dedicated branches
if ($SourceType -eq "local" -and -not $UseCurrentBranch) {
    Push-Location $ResolvedPath
    try {
        # Determine agent branch (handle case where Branch is already agent/branch format)
        if (Test-AgentBranch $Branch) {
            $AgentBranchName = $Branch
        } else {
            $AgentBranchName = "$Agent/$Branch"
        }
        
        git show-ref --verify --quiet "refs/heads/$AgentBranchName" 2>$null | Out-Null
        $BranchExistsCode = $LASTEXITCODE
        
        if ($BranchExistsCode -eq 0) {
            Write-Host ""
            Write-Host "⚠️  Warning: Branch '$AgentBranchName' already exists in the repository" -ForegroundColor Yellow
            
            # Check for unmerged commits
            $currentBranch = git branch --show-current 2>$null
            $unmergedCommits = git log "$currentBranch..$AgentBranchName" --oneline 2>$null
            
            if ($unmergedCommits) {
                Write-Host "   Branch has unmerged commits:" -ForegroundColor Yellow
                $unmergedCommits | Select-Object -First 5 | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
                if (($unmergedCommits | Measure-Object -Line).Lines -gt 5) {
                    Write-Host "     ... and $(($unmergedCommits | Measure-Object -Line).Lines - 5) more" -ForegroundColor Gray
                }
            }
            
            if (-not $Force) {
                $response = Read-Host "   Replace this branch? [y/N]"
                if ($response -ne 'y' -and $response -ne 'Y') {
                    Write-Host "❌ Launch cancelled. Use a different branch name or add -Force to replace" -ForegroundColor Red
                    Pop-Location
                    exit 1
                }
            } else {
                Write-Host "   -Force specified, will replace branch" -ForegroundColor Cyan
            }
            
            # Handle old branch
            if ($unmergedCommits) {
                # Rename old branch to preserve unmerged commits
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $archiveBranch = "${AgentBranchName}-archived-${timestamp}"
                Write-Host "   📦 Archiving old branch as: $archiveBranch" -ForegroundColor Cyan
                git branch -m "$AgentBranchName" "$archiveBranch" 2>$null | Out-Null
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "   ✅ Old branch preserved with unmerged commits" -ForegroundColor Green
                } else {
                    Write-Host "   ❌ Failed to archive old branch" -ForegroundColor Red
                    Pop-Location
                    exit 1
                }
            } else {
                # No unmerged commits, safe to delete
                Write-Host "   🗑️  Removing old branch (no unmerged commits)" -ForegroundColor Cyan
                git branch -D "$AgentBranchName" 2>$null | Out-Null
                
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "   ❌ Failed to remove old branch" -ForegroundColor Red
                    Pop-Location
                    exit 1
                }
            }
            
            Write-Host ""
        }
        
    } finally {
        Pop-Location
    }
}

# Sanitize branch name for container naming
# Remove or replace characters not allowed in Docker container names
$SafeBranch = $Branch -replace '[/\\]', '-'  # Replace slashes
$SafeBranch = $SafeBranch -replace '[^a-zA-Z0-9._-]', '-'  # Replace any other invalid chars
$SafeBranch = $SafeBranch -replace '-+', '-'  # Collapse multiple dashes
$SafeBranch = $SafeBranch -replace '^[-._]+', ''  # Remove leading special chars
$SafeBranch = $SafeBranch -replace '[-._]+$', ''  # Remove trailing special chars
$SafeBranch = $SafeBranch.ToLower()

# Ensure non-empty result
if ([string]::IsNullOrEmpty($SafeBranch)) {
    $SafeBranch = "branch"
}

# Determine container names
if ($Name) {
    # Validate custom name
    if (-not (Test-ValidContainerName $Name)) {
        Write-Host "❌ Error: Invalid container name: $Name" -ForegroundColor Red
        Write-Host "   Container names must start with alphanumeric and contain only: a-z, A-Z, 0-9, _, ., -" -ForegroundColor Yellow
        exit 1
    }
    $ContainerName = "$Agent-$Name"
    $WorkspaceName = $Name
} else {
    $ContainerName = "$Agent-$RepoName-$SafeBranch"
    $WorkspaceName = $RepoName
}

# Final validation of generated container name
if (-not (Test-ValidContainerName $ContainerName)) {
    Write-Host "❌ Error: Generated container name is invalid: $ContainerName" -ForegroundColor Red
    Write-Host "   This may be due to special characters in the repository name or branch" -ForegroundColor Yellow
    Write-Host "   Try using the -Name parameter to specify a custom name" -ForegroundColor Yellow
    exit 1
}

# Set AgentBranch (handle case where Branch is already agent/branch format or using current branch)
if ($UseCurrentBranch) {
    $AgentBranch = $Branch
} elseif (Test-AgentBranch $Branch) {
    $AgentBranch = $Branch
} else {
    $AgentBranch = "$Agent/$Branch"
}

$ProxyContainerName = "$ContainerName-proxy"
$ProxyNetworkName = "$ContainerName-net"
$ProxyImage = "coding-agents-proxy:local"

# Pull latest image
Update-AgentImage -Agent $Agent
$ImageName = "coding-agents-${Agent}:local"

# Validate image name
if (-not (Test-ValidImageName $ImageName)) {
    Write-Host "❌ Error: Invalid image name: $ImageName" -ForegroundColor Red
    exit 1
}

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
        $ExistingProxy = Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.proxy-container" }}' $ContainerName 2>$null
        $ExistingNetwork = Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.proxy-network" }}' $ContainerName 2>$null
        if ($ExistingProxy) { $ProxyContainerName = $ExistingProxy }
        if ($ExistingNetwork) { $ProxyNetworkName = $ExistingNetwork }
        Initialize-SquidProxy -NetworkName $ProxyNetworkName -ProxyContainer $ProxyContainerName -ProxyImage $ProxyImage -AgentContainer $ContainerName -SquidAllowedDomains $SquidAllowedDomains
    }
    
    if ($State -eq "running") {
        Write-Host "✅ Container is already running" -ForegroundColor Green
        Write-Host "   Connect via: $ContainerCli exec -it $ContainerName bash" -ForegroundColor Gray
        Write-Host "   Or use VS Code Dev Containers extension" -ForegroundColor Gray
        exit 0
    } else {
        Write-Host "▶️  Starting existing container..." -ForegroundColor Cyan
        Invoke-ContainerCli start $ContainerName | Out-Null
        Write-Host "✅ Container started" -ForegroundColor Green
        exit 0
    }
}

# Setup squid proxy if needed
if ($UseSquid) {
    Initialize-SquidProxy -NetworkName $ProxyNetworkName -ProxyContainer $ProxyContainerName -ProxyImage $ProxyImage -AgentContainer $ContainerName -SquidAllowedDomains $SquidAllowedDomains
}

# Build docker arguments
$autoPushValue = if ($NoPush) { "false" } else { "true" }

$dockerArgs = @(
    "run", "-d", "--rm",
    "--name", $ContainerName,
    "--hostname", $ContainerName,
    "-e", "TZ=$TimeZone",
    "-e", "SOURCE_TYPE=$SourceType",
    "-e", "REPO_NAME=$WorkspaceName",
    "-e", "AGENT_BRANCH=$AgentBranch",
    "-e", "NETWORK_POLICY=$NetworkPolicyEnv",
    "-e", "AUTO_PUSH_ON_SHUTDOWN=$autoPushValue",
    "-e", "AGENT_SESSION_MODE=supervised",
    "-e", "AGENT_SESSION_NAME=agent",
    "--label", "coding-agents.type=agent",
    "--label", "coding-agents.agent=$Agent",
    "--label", "coding-agents.repo=$RepoName",
    "--label", "coding-agents.branch=$AgentBranch",
    "--label", "coding-agents.network-policy=$NetworkPolicyEnv"
)

# Add repo path label for local repos (for cleanup)
if ($SourceType -eq "local") {
    $dockerArgs += "--label", "coding-agents.repo-path=$ResolvedPath"
}

$dockerArgs += @(
    "-v", "${WslHome}/.gitconfig:/home/agentuser/.gitconfig:ro",
    "-v", "${WslHome}/.config/gh:/home/agentuser/.config/gh:ro",
    "-v", "${WslHome}/.config/github-copilot:/home/agentuser/.config/github-copilot:ro"
)

# Add source-specific vars
if ($SourceType -eq "url") {
    $dockerArgs += "-e", "GIT_URL=$GitUrl"
} else {
    $localRepoEnvValue = if ($LocalRepoPathValue) { $LocalRepoPathValue } else { $WslPath }
    $dockerArgs += "-e", "LOCAL_REPO_PATH=$localRepoEnvValue"
    $dockerArgs += "-v", "${WslPath}:/tmp/source-repo:ro"
    if (-not [string]::IsNullOrEmpty($LocalRemoteWslPath)) {
        $dockerArgs += "-e", "LOCAL_REMOTE_URL=$LocalRemoteUrl"
        $dockerArgs += "-v", "${LocalRemoteWslPath}:/tmp/local-remote"
        if (-not [string]::IsNullOrEmpty($LocalRemoteHostPath)) {
            $dockerArgs += "--label", "coding-agents.local-remote=$LocalRemoteHostPath"
        }
    }
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

# Start git credential proxy server on host if not already running
$credentialSocketPath = "${WslHome}/.config/coding-agents/git-credential.sock"
$credentialProxyScript = Join-Path $PSScriptRoot "..\runtime\git-credential-proxy-server.sh"

if (-not (Test-Path $credentialSocketPath -PathType Leaf)) {
    if (Test-Path $credentialProxyScript) {
        Write-Host "🔐 Starting git credential proxy server..." -ForegroundColor Cyan
        $proxyDir = Split-Path $credentialSocketPath -Parent
        if (-not (Test-Path $proxyDir)) {
            New-Item -ItemType Directory -Path $proxyDir -Force | Out-Null
        }
        
        # Start proxy server in background using WSL bash
        Start-Process -FilePath "wsl" -ArgumentList "bash", "-c", "`"nohup '$credentialProxyScript' '$credentialSocketPath' > /dev/null 2>&1 &`"" -NoNewWindow | Out-Null
        
        # Wait for socket to be created (max 5 seconds)
        $waited = 0
        while (-not (Test-Path $credentialSocketPath -PathType Leaf) -and $waited -lt 5000) {
            Start-Sleep -Milliseconds 100
            $waited += 100
        }
        
        if (Test-Path $credentialSocketPath -PathType Leaf) {
            Write-Host "   ✅ Credential proxy started" -ForegroundColor Green
        } else {
            Write-Warning "   ⚠️  Credential proxy started but socket not ready"
            Write-Warning "      Container will fall back to file-based credentials"
        }
    } else {
        Write-Warning "⚠️  Credential proxy script not found, using file-based credentials"
    }
}

# Start GPG proxy server on host if not already running and GPG signing is configured
$gpgSocketPath = "${WslHome}/.config/coding-agents/gpg-proxy.sock"
$gpgProxyScript = Join-Path $PSScriptRoot "..\runtime\gpg-proxy-server.sh"

$commitGpgSign = wsl bash -c "git config commit.gpgsign 2>/dev/null"
$gpgSigningEnabled = $false
if ($commitGpgSign -eq "true") {
    $gpgSigningEnabled = $true
    if (-not (Test-Path $gpgSocketPath -PathType Leaf)) {
        if (Test-Path $gpgProxyScript) {
            Write-Host "🔏 Starting GPG proxy server for commit signing..." -ForegroundColor Cyan
            $gpgProxyDir = Split-Path $gpgSocketPath -Parent
            if (-not (Test-Path $gpgProxyDir)) {
                New-Item -ItemType Directory -Path $gpgProxyDir -Force | Out-Null
            }
            
            # Start GPG proxy server in background
            Start-Process -FilePath "wsl" -ArgumentList "bash", "-c", "`"nohup '$gpgProxyScript' '$gpgSocketPath' > /dev/null 2>&1 &`"" -NoNewWindow
            
            # Wait for socket to be created
            $waited = 0
            while (-not (Test-Path $gpgSocketPath -PathType Leaf) -and $waited -lt 5000) {
                Start-Sleep -Milliseconds 100
                $waited += 100
            }
            
            if (Test-Path $gpgSocketPath -PathType Leaf) {
                Write-Host "   ✅ GPG proxy started" -ForegroundColor Green
            }
        }
    }
}

# Mount credential proxy socket (most secure - no files in container)
if (Test-Path $credentialSocketPath -PathType Leaf) {
    $dockerArgs += "-v", "${credentialSocketPath}:/tmp/git-credential-proxy.sock:ro"
    $dockerArgs += "-e", "CREDENTIAL_SOCKET=/tmp/git-credential-proxy.sock"
}

# Mount GPG proxy socket (secure signing - private keys stay on host)
if (Test-Path $gpgSocketPath -PathType Leaf) {
    $dockerArgs += "-v", "${gpgSocketPath}:/tmp/gpg-proxy.sock:ro"
    $dockerArgs += "-e", "GPG_PROXY_SOCKET=/tmp/gpg-proxy.sock"
}

# Fallback: Mount credential files (read-only for security)
# These are only used if socket proxy is not available
if (Test-Path "${WslHome}/.git-credentials") { $dockerArgs += "-v", "${WslHome}/.git-credentials:/home/agentuser/.git-credentials:ro" }

# SSH agent socket forwarding (supports any SSH agent via standard SSH_AUTH_SOCK)
$sshAuthSock = $env:SSH_AUTH_SOCK
$sshAgentSocketMounted = $false
if ($sshAuthSock -and (Test-Path $sshAuthSock)) {
    # Forward SSH agent socket to container
    $dockerArgs += "-v", "${sshAuthSock}:/tmp/ssh-agent.sock:ro"
    $dockerArgs += "-e", "SSH_AUTH_SOCK=/tmp/ssh-agent.sock"
    $sshAgentSocketMounted = $true
}

if (-not $sshAgentSocketMounted -and (Test-Path "${WslHome}/.ssh")) {
    Write-Warning "⚠️  SSH agent socket not available; host SSH keys will not be forwarded. Start ssh-agent before running run-agent.ps1."
}

if ($gpgSigningEnabled -and -not (Test-Path $gpgSocketPath -PathType Leaf)) {
    Write-Warning "⚠️  Commit signing is enabled but the gpg-proxy socket was not created. Signing will be disabled; run gpg-proxy-server.sh or disable commit.gpgsign."
}

# Final args
$dockerArgs += "-w", "/workspace"
$dockerArgs += "--network", $NetworkMode
$dockerArgs += "--cap-drop=ALL"
$dockerArgs += "--security-opt", "no-new-privileges:true"
$dockerArgs += "--pids-limit=4096"

# Add resource limits
$dockerArgs += "--cpus=$Cpu"
$dockerArgs += "--memory=$Memory"
$dockerArgs += "--memory-swap=$Memory"
if ($Gpu) {
    $dockerArgs += "--gpus=$Gpu"
}

$extraArgsEnv = $env:CODING_AGENTS_EXTRA_DOCKER_ARGS
if ($extraArgsEnv) {
    $errors = $null
    $tokens = [System.Management.Automation.PSParser]::Tokenize($extraArgsEnv, [ref]$errors)
    foreach ($token in $tokens) {
        if ($token.Type -in @('CommandArgument','String')) {
            $dockerArgs += $token.Content
        }
    }
}

$dockerArgs += $ImageName

# Create container
Write-Host "📦 Creating container..." -ForegroundColor Cyan
try {
    Invoke-ContainerCli @dockerArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Container create failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "❌ Failed to create container" -ForegroundColor Red
    if ($UseSquid) {
        Invoke-ContainerCli rm -f $ProxyContainerName 2>$null | Out-Null
        Invoke-ContainerCli network rm $ProxyNetworkName 2>$null | Out-Null
    }
    exit 1
}

# Setup repository inside container
Write-Host "📥 Setting up repository..." -ForegroundColor Cyan
$setupScript = New-RepoSetupScript

try {
    $setupScript | & $ContainerCli exec -i $ContainerName bash
    if ($LASTEXITCODE -ne 0) {
        throw "Container setup failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "❌ Failed to setup repository" -ForegroundColor Red
    Invoke-ContainerCli rm -f $ContainerName | Out-Null
    exit 1
}

if ($UseSquid) {
    Start-Job -ScriptBlock {
        param($CliCmd, $AgentContainer, $ProxyContainer, $ProxyNetwork)
        try {
            & $CliCmd wait $AgentContainer | Out-Null
        } catch {
            # Ignore errors if container already gone
        }
        & $CliCmd rm -f $ProxyContainer 2>$null | Out-Null
        & $CliCmd network rm $ProxyNetwork 2>$null | Out-Null
    } -ArgumentList $ContainerCli, $ContainerName, $ProxyContainerName, $ProxyNetworkName | Out-Null
}

Write-Host ""
Write-Host "✅ Container '$ContainerName' is ready!" -ForegroundColor Green
Write-Host "🔗 Attaching to agent session (detach with Ctrl+B, then D)..." -ForegroundColor Cyan
& $ContainerCli exec -it $ContainerName agent-session attach
$attachExit = $LASTEXITCODE

if ($attachExit -ne 0) {
    if ((Get-ContainerStatus $ContainerName) -eq "running") {
        $connectScript = Join-Path $scriptDir "connect-agent.ps1"
        Write-Host "⚠ Unable to attach automatically. Re-run: `n   $connectScript -Name $ContainerName" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Agent session exited before it was ready." -ForegroundColor Red
    }
    exit $attachExit
}

if ((Get-ContainerStatus $ContainerName) -eq "running") {
    $connectScript = Join-Path $scriptDir "connect-agent.ps1"
    Write-Host ""
    Write-Host "ℹ Session detached but container is still running." -ForegroundColor Cyan
    Write-Host "   Reconnect: $connectScript -Name $ContainerName" -ForegroundColor Gray
    Write-Host "   Stop later: $ContainerCli stop $ContainerName" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "✅ Agent session complete. Container stopped." -ForegroundColor Green
}

if ($SourceType -eq "local" -and -not $NoPush -and -not [string]::IsNullOrWhiteSpace($LocalRemoteHostPath)) {
    Write-Host "🔄 Syncing agent branch back to host repository..." -ForegroundColor Cyan
    Sync-LocalRemoteToHost -RepoPath $ResolvedPath -LocalRemotePath $LocalRemoteHostPath -AgentBranch $AgentBranch
}
