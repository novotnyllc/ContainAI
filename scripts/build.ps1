# Build script for the coding agents containers (PowerShell)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

Set-Location $ProjectDir

Write-Host "🏗️  Building Coding Agents Containers" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is running
try {
    docker info | Out-Null
} catch {
    Write-Host "❌ Docker is not running!" -ForegroundColor Red
    Write-Host "   Please start Docker and try again" -ForegroundColor Yellow
    exit 1
}

# Ask user which base image to use
Write-Host "Select base image source:" -ForegroundColor Yellow
Write-Host "1) Pull from GitHub Container Registry (recommended)"
Write-Host "2) Build locally (takes ~15 minutes)"
$choice = Read-Host "Enter choice (1 or 2)"

switch ($choice) {
    "1" {
        $gh_username = Read-Host "Enter GitHub username for base image"
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
        docker build -f Dockerfile.base -t coding-agents-base:local .
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
docker build --build-arg BASE_IMAGE=$BASE_IMAGE -t coding-agents:local .
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to build all-agents image" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🔨 Building individual agent images..." -ForegroundColor Cyan
docker build -f Dockerfile.copilot --build-arg BASE_IMAGE=coding-agents:local -t coding-agents-copilot:local .
docker build -f Dockerfile.codex --build-arg BASE_IMAGE=coding-agents:local -t coding-agents-codex:local .
docker build -f Dockerfile.claude --build-arg BASE_IMAGE=coding-agents:local -t coding-agents-claude:local .

Write-Host ""
Write-Host "🔨 Building network proxy image..." -ForegroundColor Cyan
docker build -f Dockerfile.proxy -t coding-agents-proxy:local .

Write-Host ""
Write-Host "✅ Build complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Images created:" -ForegroundColor Cyan
Write-Host "  • coding-agents:local (all agents, interactive shell)"
Write-Host "  • coding-agents-copilot:local (launches Copilot directly)"
Write-Host "  • coding-agents-codex:local (launches Codex directly)"
Write-Host "  • coding-agents-claude:local (launches Claude directly)"
Write-Host "  • coding-agents-proxy:local (Squid network proxy sidecar)"
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
