# Common functions for agent management scripts (PowerShell)

function Test-ValidContainerName {
    param([string]$Name)
    # Container names must match: [a-zA-Z0-9][a-zA-Z0-9_.-]*
    if ($Name -match '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') {
        return $true
    }
    return $false
}

function Test-ValidBranchName {
    param([string]$Branch)
    # Basic git branch name validation - no spaces, no special chars that git doesn't allow
    if ($Branch -match '^[a-zA-Z0-9][a-zA-Z0-9/_.-]*$' -and $Branch -notmatch '\.\.' -and $Branch -notmatch '/$') {
        return $true
    }
    return $false
}

function Test-ValidImageName {
    param([string]$Image)
    # Docker image name validation
    if ($Image -match '^[a-z0-9]+(([._-]|__)[a-z0-9]+)*(:[a-zA-Z0-9_.-]+)?$') {
        return $true
    }
    return $false
}

function Get-RepoName {
    param([string]$RepoPath)
    Split-Path -Leaf $RepoPath
}

function Get-CurrentBranch {
    param([string]$RepoPath)
    Push-Location $RepoPath
    $branch = git branch --show-current 2>$null
    Pop-Location
    if ($branch) { return $branch } else { return "main" }
}

function Test-DockerRunning {
    try {
        docker info | Out-Null
        return $true
    } catch {
        Write-Host "❌ Docker is not running!" -ForegroundColor Red
        Write-Host "   Please start Docker and try again" -ForegroundColor Yellow
        return $false
    }
}

function Update-AgentImage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Agent,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory=$false)]
        [int]$RetryDelaySeconds = 2
    )
    
    $registryImage = "ghcr.io/novotnyllc/coding-agents-${Agent}:latest"
    $localImage = "coding-agents-${Agent}:local"
    
    Write-Host "📦 Checking for image updates..." -ForegroundColor Cyan
    
    # Try to pull with retries
    $attempt = 0
    $pulled = $false
    
    while ($attempt -lt $MaxRetries -and -not $pulled) {
        $attempt++
        try {
            if ($attempt -gt 1) {
                Write-Host "  Retry attempt $attempt of $MaxRetries..." -ForegroundColor Yellow
            }
            docker pull --quiet $registryImage 2>$null | Out-Null
            docker tag $registryImage $localImage 2>$null | Out-Null
            $pulled = $true
        } catch {
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }
    
    if (-not $pulled) {
        Write-Host "  ⚠️  Warning: Could not pull latest image, using cached version" -ForegroundColor Yellow
    }
}

function Test-ContainerExists {
    param([string]$ContainerName)
    $existing = docker ps -a --filter "name=^${ContainerName}$" --format "{{.Names}}" 2>$null
    return ($existing -eq $ContainerName)
}

function Get-ContainerStatus {
    param([string]$ContainerName)
    $status = docker inspect -f '{{.State.Status}}' $ContainerName 2>$null
    if ($status) { return $status } else { return "not-found" }
}

function Push-ToLocal {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipPush
    )
    
    if ($SkipPush) {
        Write-Host "⏭️  Skipping git push (--no-push specified)" -ForegroundColor Yellow
        return
    }
    
    Write-Host "💾 Pushing changes to local remote..." -ForegroundColor Cyan
    
    $pushScript = @'
cd /workspace
if [ -n "$(git status --porcelain)" ]; then
    echo "📝 Uncommitted changes detected"
    read -p "Commit changes before push? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Commit message: " msg
        git add -A
        git commit -m "$msg"
    fi
fi

if git push 2>&1; then
    echo "✅ Changes pushed to local remote"
else
    echo "⚠️  Failed to push (may be up to date)"
fi
'@
    
    try {
        $pushScript | docker exec -i $ContainerName bash 2>$null
    } catch {
        Write-Host "⚠️  Could not push changes" -ForegroundColor Yellow
    }
}

function Get-AgentContainers {
    docker ps -a --filter "label=coding-agents.type=agent" `
        --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CreatedAt}}"
}

function Get-ProxyContainer {
    param([string]$AgentContainer)
    docker inspect -f '{{ index .Config.Labels "coding-agents.proxy-container" }}' $AgentContainer 2>$null
}

function Get-ProxyNetwork {
    param([string]$AgentContainer)
    docker inspect -f '{{ index .Config.Labels "coding-agents.proxy-network" }}' $AgentContainer 2>$null
}

function Remove-ContainerWithSidecars {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipPush
    )
    
    if (-not (Test-ContainerExists $ContainerName)) {
        Write-Host "❌ Container '$ContainerName' does not exist" -ForegroundColor Red
        return $false
    }
    
    # Push changes first
    if ((Get-ContainerStatus $ContainerName) -eq "running") {
        Push-ToLocal -ContainerName $ContainerName -SkipPush:$SkipPush
    }
    
    # Get associated resources
    $proxyContainer = Get-ProxyContainer $ContainerName
    $proxyNetwork = Get-ProxyNetwork $ContainerName
    
    # Remove main container
    Write-Host "🗑️  Removing container: $ContainerName" -ForegroundColor Cyan
    docker rm -f $ContainerName 2>$null | Out-Null
    
    # Remove proxy if exists
    if ($proxyContainer -and (Test-ContainerExists $proxyContainer)) {
        Write-Host "🗑️  Removing proxy: $proxyContainer" -ForegroundColor Cyan
        docker rm -f $proxyContainer 2>$null | Out-Null
    }
    
    # Remove network if exists and no containers attached
    if ($proxyNetwork) {
        $attached = docker network inspect -f '{{range .Containers}}{{.Name}} {{end}}' $proxyNetwork 2>$null
        if (-not $attached) {
            Write-Host "🗑️  Removing network: $proxyNetwork" -ForegroundColor Cyan
            docker network rm $proxyNetwork 2>$null | Out-Null
        }
    }
    
    Write-Host "✅ Cleanup complete" -ForegroundColor Green
    return $true
}

function Ensure-SquidProxy {
    param(
        [Parameter(Mandatory=$true)]
        [string]$NetworkName,
        
        [Parameter(Mandatory=$true)]
        [string]$ProxyContainer,
        
        [Parameter(Mandatory=$true)]
        [string]$ProxyImage,
        
        [Parameter(Mandatory=$true)]
        [string]$AgentContainer,
        
        [Parameter(Mandatory=$false)]
        [string]$SquidAllowedDomains = "*.github.com,*.githubcopilot.com,*.nuget.org"
    )
    
    # Validate inputs
    if (-not (Test-ValidContainerName $ProxyContainer)) {
        Write-Host "❌ Error: Invalid proxy container name: $ProxyContainer" -ForegroundColor Red
        throw "Invalid proxy container name"
    }
    
    if ([string]::IsNullOrWhiteSpace($SquidAllowedDomains)) {
        Write-Host "⚠️  Warning: No allowed domains specified for proxy" -ForegroundColor Yellow
        $SquidAllowedDomains = "*.github.com"
    }
    
    # Create network if needed
    $networkExists = docker network inspect $NetworkName 2>$null
    if (-not $networkExists) {
        docker network create $NetworkName | Out-Null
    }
    
    # Check if proxy exists
    if (Test-ContainerExists $ProxyContainer) {
        $state = Get-ContainerStatus $ProxyContainer
        if ($state -ne "running") {
            docker start $ProxyContainer | Out-Null
        }
    } else {
        # Create new proxy
        docker run -d `
            --name $ProxyContainer `
            --hostname $ProxyContainer `
            --network $NetworkName `
            --restart unless-stopped `
            -e "SQUID_ALLOWED_DOMAINS=$SquidAllowedDomains" `
            --label "coding-agents.proxy-of=$AgentContainer" `
            --label "coding-agents.proxy-image=$ProxyImage" `
            $ProxyImage | Out-Null
    }
}

function New-RepoSetupScript {
    return @'
#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="/workspace"
mkdir -p "$TARGET_DIR"

# Clean target directory
if [ -d "$TARGET_DIR" ] && [ "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

if [ "$SOURCE_TYPE" = "url" ]; then
    echo "🌐 Cloning repository from $GIT_URL..."
    git clone "$GIT_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
    if [ -n "$ORIGIN_URL" ]; then
        git remote set-url origin "$ORIGIN_URL"
    fi
else
    echo "📁 Copying repository from host..."
    cp -a /tmp/source-repo/. "$TARGET_DIR/"
    cd "$TARGET_DIR"
    
    # Configure local remote
    if [ -n "$LOCAL_REPO_PATH" ]; then
        if ! git remote get-url local >/dev/null 2>&1; then
            git remote add local "$LOCAL_REPO_PATH"
        fi
        git config remote.pushDefault local
    fi
fi

# Create and checkout branch
if [ -n "$AGENT_BRANCH" ]; then
    BRANCH_NAME="$AGENT_BRANCH"
    if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        git checkout -b "$BRANCH_NAME"
    else
        git checkout "$BRANCH_NAME"
    fi
fi

echo "✅ Repository setup complete"
'@
}
