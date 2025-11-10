# PowerShell script to run the coding agent container with a specific repository

param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerName,
    
    [Parameter(Mandatory=$false)]
    [string]$Agent = "all"
)

$ErrorActionPreference = "Stop"

# Resolve the full path
$RepoPath = Resolve-Path $RepoPath -ErrorAction SilentlyContinue
if (-not $RepoPath) {
    Write-Host "❌ Error: Repository path does not exist" -ForegroundColor Red
    exit 1
}

# Convert Windows path to WSL path
$WslPath = $RepoPath -replace '^([A-Z]):', { '/mnt/' + $_.Groups[1].Value.ToLower() } -replace '\\', '/'

# Get container name
if (-not $ContainerName) {
    $ContainerName = Split-Path -Leaf $RepoPath
}

# Auto-detect WSL home directory
$WslHome = wsl bash -c 'echo $HOME' 2>$null
if (-not $WslHome) {
    Write-Host "❌ Error: Could not detect WSL home directory" -ForegroundColor Red
    Write-Host "   Make sure WSL2 is installed and running" -ForegroundColor Yellow
    exit 1
}

# Get timezone from host
$TimeZone = (Get-TimeZone).Id

# Check if it's a git repository
if (-not (Test-Path (Join-Path $RepoPath ".git"))) {
    Write-Host "⚠️  Warning: $RepoPath is not a git repository" -ForegroundColor Yellow
    $response = Read-Host "Continue anyway? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        exit 1
    }
}

# Select image based on agent parameter
$ImageName = switch ($Agent) {
    "copilot" { "coding-agents-copilot:local" }
    "codex" { "coding-agents-codex:local" }
    "claude" { "coding-agents-claude:local" }
    default { "coding-agents:local" }
}

Write-Host "🚀 Starting coding agent container..." -ForegroundColor Cyan
Write-Host "📁 Repository: $RepoPath" -ForegroundColor Cyan
Write-Host "🐧 WSL Path: $WslPath" -ForegroundColor Cyan
Write-Host "🏷️  Container: $Agent-$ContainerName" -ForegroundColor Cyan
Write-Host "🎯 Image: $ImageName" -ForegroundColor Cyan
Write-Host ""

# Build docker arguments
$dockerArgs = @(
    "run", "-it", "--rm",
    "--name", "$Agent-$ContainerName",
    "--hostname", "coding-agent",
    "-e", "TZ=$TimeZone",
    "-v", "${WslPath}:/workspace",
    "-v", "${WslHome}/.gitconfig:/home/agentuser/.gitconfig:ro",
    "-v", "${WslHome}/.config/gh:/home/agentuser/.config/gh:ro",
    "-v", "${WslHome}/.config/github-copilot:/home/agentuser/.config/github-copilot:ro"
)

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
    "--network", "bridge",
    "--security-opt", "no-new-privileges:true",
    "--cpus=4",
    "--memory=8g",
    $ImageName
)

& docker $dockerArgs

Write-Host ""
Write-Host "👋 Container stopped." -ForegroundColor Green
