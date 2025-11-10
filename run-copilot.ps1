# Ultra-simple launcher for GitHub Copilot
# Usage: .\run-copilot.ps1 [directory]
#   directory: Path to repository (defaults to current directory)

param(
    [Parameter(Mandatory=$false)]
    [string]$RepoPath = "."
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
$RepoName = Split-Path -Leaf $RepoPath

# Auto-detect WSL home directory (works for any username)
$WslHome = wsl bash -c 'echo $HOME' 2>$null
if (-not $WslHome) {
    Write-Host "❌ Error: Could not detect WSL home directory" -ForegroundColor Red
    Write-Host "   Make sure WSL2 is installed and running" -ForegroundColor Yellow
    exit 1
}

# Get timezone from host
$TimeZone = (Get-TimeZone).Id

Write-Host "🚀 Launching GitHub Copilot CLI..." -ForegroundColor Cyan
Write-Host "📁 Repository: $RepoPath" -ForegroundColor Cyan

docker run -it --rm `
    --name "copilot-$RepoName" `
    -e "TZ=$TimeZone" `
    -v "${WslPath}:/workspace" `
    -v "${WslHome}/.gitconfig:/home/agentuser/.gitconfig:ro" `
    -v "${WslHome}/.config/gh:/home/agentuser/.config/gh:ro" `
    -v "${WslHome}/.config/github-copilot:/home/agentuser/.config/github-copilot:ro" `
    -w /workspace `
    --security-opt no-new-privileges:true `
    coding-agents-copilot:local
