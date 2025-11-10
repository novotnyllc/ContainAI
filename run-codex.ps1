# Ultra-simple launcher for OpenAI Codex
# Usage: .\run-codex.ps1 [directory]
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

# Auto-detect WSL home directory
$WslHome = wsl bash -c 'echo $HOME' 2>$null
if (-not $WslHome) {
    Write-Host "❌ Error: Could not detect WSL home directory" -ForegroundColor Red
    exit 1
}

# Get timezone from host
$TimeZone = (Get-TimeZone).Id

Write-Host "🚀 Launching OpenAI Codex..." -ForegroundColor Cyan
Write-Host "📁 Repository: $RepoPath" -ForegroundColor Cyan

# Build docker command with optional mounts
$dockerArgs = @(
    "run", "-it", "--rm",
    "--name", "codex-$RepoName",
    "-e", "TZ=$TimeZone",
    "-v", "${WslPath}:/workspace",
    "-v", "${WslHome}/.gitconfig:/home/agentuser/.gitconfig:ro",
    "-v", "${WslHome}/.config/gh:/home/agentuser/.config/gh:ro"
)

# Add Codex config if it exists
if (wsl test -d "${WslHome}/.config/codex") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/codex:/home/agentuser/.config/codex:ro"
}

# Add MCP secrets if they exist
if (wsl test -f "${WslHome}/.config/coding-agents/mcp-secrets.env") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/coding-agents/mcp-secrets.env:/home/agentuser/.mcp-secrets.env:ro"
}

$dockerArgs += @("-w", "/workspace", "--security-opt", "no-new-privileges:true", "coding-agents-codex:local")

& docker $dockerArgs
