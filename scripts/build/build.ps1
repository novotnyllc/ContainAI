# Build script for the coding agents containers (PowerShell)

param(
    [Parameter(Mandatory = $false)]
    [string[]]$Agents
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

$defaultTargets = @("copilot", "codex", "claude", "proxy")
$agentImages = @("copilot", "codex", "claude")

function Get-NormalizedTargets {
    param([string[]]$Requested)

    if (-not $Requested -or $Requested.Count -eq 0) {
        return ,$defaultTargets
    }

    $chosen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $normalized = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $Requested) {
        foreach ($token in ($entry -split ',')) {
            $value = $token.Trim().ToLower()
            if (-not $value) { continue }

            if ($value -eq 'all') {
                return ,$defaultTargets
            }

            if ($defaultTargets -notcontains $value) {
                throw "Invalid agent target '$value'. Valid options: copilot, codex, claude, proxy, all"
            }

            if ($chosen.Add($value)) {
                $normalized.Add($value) | Out-Null
            }
        }
    }

    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $defaultTargets) {
        if ($normalized -contains $candidate) {
            $ordered.Add($candidate) | Out-Null
        }
    }

    return ,$ordered.ToArray()
}

try {
    $selectedTargets = Get-NormalizedTargets -Requested $Agents
} catch {
    Write-Host "❌ $_" -ForegroundColor Red
    exit 1
}

$agentsToBuild = @()
foreach ($candidate in $agentImages) {
    if ($selectedTargets -contains $candidate) {
        $agentsToBuild += $candidate
    }
}

$shouldBuildProxy = $selectedTargets -contains 'proxy'
$needsAgentImages = $agentsToBuild.Count -gt 0
$builtImages = New-Object System.Collections.Generic.List[string]

Set-Location $ProjectDir

Write-Host "🏗️  Building Coding Agents Containers" -ForegroundColor Cyan
Write-Host "🎯 Targets: $($selectedTargets -join ', ')" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is running
try {
    docker info | Out-Null
} catch {
    Write-Host "❌ Docker is not running!" -ForegroundColor Red
    Write-Host "   Please start Docker and try again" -ForegroundColor Yellow
    exit 1
}

$BASE_IMAGE = $null

if ($needsAgentImages) {
    Write-Host "Select base image source:" -ForegroundColor Yellow
    Write-Host "1) Pull from GitHub Container Registry (recommended)"
    Write-Host "2) Build locally (takes ~15 minutes)"
    $choice = Read-Host "Enter choice (1 or 2)"

    switch ($choice) {
        "1" {
            $gh_username = Read-Host "Enter GitHub username or org for base image [novotnyllc]"
            if ([string]::IsNullOrWhiteSpace($gh_username)) { $gh_username = "novotnyllc" }
            $BASE_IMAGE = "ghcr.io/$gh_username/coding-agents-base:latest"
            Write-Host ""
            Write-Host "📥 Pulling base image: $BASE_IMAGE" -ForegroundColor Cyan
            docker pull $BASE_IMAGE
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Failed to pull base image" -ForegroundColor Red
                Write-Host "   Make sure the image exists and you're authenticated:" -ForegroundColor Yellow
                Write-Host "   docker login ghcr.io" -ForegroundColor Yellow
                exit 1
            }
        }
        "2" {
            Write-Host ""
            Write-Host "🔨 Building base image locally..." -ForegroundColor Cyan
            Write-Host "   This will take approximately 15 minutes..." -ForegroundColor Yellow
            docker build -f docker/base/Dockerfile -t coding-agents-base:local .
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Failed to build base image" -ForegroundColor Red
                exit 1
            }
            $BASE_IMAGE = "coding-agents-base:local"
        }
        default {
            Write-Host "Invalid choice" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host ""
    Write-Host "🔨 Building all-agents image..." -ForegroundColor Cyan
    docker build -f docker/agents/all/Dockerfile --build-arg BASE_IMAGE=$BASE_IMAGE -t coding-agents:local .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to build all-agents image" -ForegroundColor Red
        exit 1
    }
    $builtImages.Add("coding-agents:local (all agents, interactive shell)") | Out-Null

    if ($agentsToBuild.Count -gt 0) {
        Write-Host ""
        Write-Host "🔨 Building selected agent images..." -ForegroundColor Cyan
        foreach ($agent in $agentsToBuild) {
            docker build -f "docker/agents/$agent/Dockerfile" --build-arg BASE_IMAGE=coding-agents:local -t "coding-agents-$agent:local" .
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Failed to build $agent image" -ForegroundColor Red
                exit 1
            }

            switch ($agent) {
                'copilot' { $builtImages.Add("coding-agents-copilot:local (launches Copilot directly)") | Out-Null }
                'codex'   { $builtImages.Add("coding-agents-codex:local (launches Codex directly)") | Out-Null }
                'claude'  { $builtImages.Add("coding-agents-claude:local (launches Claude directly)") | Out-Null }
            }
        }
    }
}

if ($shouldBuildProxy) {
    Write-Host ""
    Write-Host "🔨 Building network proxy image..." -ForegroundColor Cyan
    docker build -f docker/proxy/Dockerfile -t coding-agents-proxy:local .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to build proxy image" -ForegroundColor Red
        exit 1
    }
    $builtImages.Add("coding-agents-proxy:local (Squid network proxy sidecar)") | Out-Null
}

Write-Host ""
Write-Host "✅ Build complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Images created:" -ForegroundColor Cyan
foreach ($image in $builtImages) {
    Write-Host "  • $image"
}
Write-Host ""
Write-Host "🚀 Run a container with:" -ForegroundColor Cyan
Write-Host "   .\scripts\run-agent.ps1 -RepoPath 'E:\dev\your-repo'" -ForegroundColor Yellow
Write-Host ""
Write-Host "   Or using docker-compose:" -ForegroundColor Cyan
Write-Host "   cp .env.example .env" -ForegroundColor Yellow
Write-Host "   # Edit .env with your repo path and WSL username" -ForegroundColor Yellow
Write-Host "   docker-compose up -d                    # All agents" -ForegroundColor Yellow
Write-Host "   docker-compose --profile copilot up -d  # Just Copilot" -ForegroundColor Yellow
Write-Host "   docker-compose --profile codex up -d    # Just Codex" -ForegroundColor Yellow
Write-Host "   docker-compose --profile claude up -d   # Just Claude" -ForegroundColor Yellow
