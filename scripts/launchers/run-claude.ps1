# Quick launcher for Anthropic Claude from current directory
# Usage: .\run-claude.ps1 [RepoPath] [-NoPush]

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$RepoPath = ".",
    
    [Parameter(Mandatory=$false)]
    [switch]$NoPush,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host "Usage: .\run-claude.ps1 [RepoPath] [-NoPush]"
    Write-Host ""
    Write-Host "Launch Anthropic Claude in an ephemeral container."
    Write-Host ""
    Write-Host "Arguments:"
    Write-Host "  RepoPath    Path to repository (default: current directory)"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -NoPush     Skip auto-push to local remote on exit"
    Write-Host "  -Help       Show this help"
    exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\..\utils\common-functions.ps1"

if (-not (Test-DockerRunning)) { exit 1 }

try {
    $RepoPath = Resolve-Path $RepoPath -ErrorAction Stop
} catch {
    Write-Host "❌ Error: Repository path does not exist: $RepoPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $RepoPath ".git"))) {
    Write-Host "❌ Error: $RepoPath is not a git repository" -ForegroundColor Red
    exit 1
}

$RepoName = Get-RepoName $RepoPath
$Branch = Get-CurrentBranch $RepoPath
$ContainerName = "claude-$RepoName-$Branch"
$WslPath = $RepoPath -replace '^([A-Z]):', { '/mnt/' + $_.Groups[1].Value.ToLower() } -replace '\\', '/'

$WslHome = wsl bash -c 'echo $HOME' 2>$null
if (-not $WslHome) {
    Write-Host "❌ Error: Could not detect WSL home directory" -ForegroundColor Red
    exit 1
}

$TimeZone = (Get-TimeZone).Id

Update-AgentImage -Agent "claude"

Write-Host "🚀 Launching Anthropic Claude..." -ForegroundColor Cyan
Write-Host "📁 Repository: $RepoName" -ForegroundColor Cyan
Write-Host "🌿 Branch: $Branch" -ForegroundColor Cyan
Write-Host "🏷️  Container: $ContainerName" -ForegroundColor Cyan
Write-Host ""

$dockerArgs = @(
    "run", "-it", "--rm",
    "--name", $ContainerName,
    "-e", "TZ=$TimeZone",
    "-v", "${WslPath}:/workspace",
    "-v", "${WslHome}/.gitconfig:/home/agentuser/.gitconfig:ro",
    "-v", "${WslHome}/.config/gh:/home/agentuser/.config/gh:ro",
    "--label", "coding-agents.type=agent",
    "--label", "coding-agents.agent=claude",
    "--label", "coding-agents.repo=$RepoName",
    "--label", "coding-agents.branch=$Branch"
)

if (wsl test -d "${WslHome}/.config/claude") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/claude:/home/agentuser/.config/claude:ro"
}

if (wsl test -f "${WslHome}/.config/coding-agents/mcp-secrets.env") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/coding-agents/mcp-secrets.env:/home/agentuser/.mcp-secrets.env:ro"
}

$dockerArgs += @(
    "-w", "/workspace",
    "--security-opt", "no-new-privileges:true",
    "coding-agents-claude:local"
)

try {
    & docker $dockerArgs
} finally {
    if (Test-ContainerExists $ContainerName) {
        Write-Host ""
        Push-ToLocal -ContainerName $ContainerName -SkipPush:$NoPush
    }
}
