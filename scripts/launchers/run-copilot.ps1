# Quick launcher for GitHub Copilot CLI from current directory
# Usage: .\run-copilot.ps1 [RepoPath] [-NoPush]
#   RepoPath: Path to repository (defaults to current directory)
#   -NoPush: Skip auto-push on exit

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$RepoPath = ".",
    
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
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host "Usage: .\run-copilot.ps1 [RepoPath] [OPTIONS]"
    Write-Host ""
    Write-Host "Launch GitHub Copilot CLI in an ephemeral container."
    Write-Host ""
    Write-Host "Arguments:"
    Write-Host "  RepoPath              Path to repository (default: current directory)"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Branch BRANCH        Branch name (creates <agent>/<branch>)"
    Write-Host "  -Name NAME            Custom container name"
    Write-Host "  -DotNetPreview CH     Install .NET preview SDK (e.g., 11.0)"
    Write-Host "  -NetworkProxy MODE    Network: allow-all, restricted, squid (default: allow-all)"
    Write-Host "  -Cpu NUM              CPU limit (default: 4)"
    Write-Host "  -Memory SIZE          Memory limit (default: 8g)"
    Write-Host "  -Gpu SPEC             GPU specification (e.g., 'all' or 'device=0')"
    Write-Host "  -NoPush               Skip auto-push to git remote on exit"
    Write-Host "  -UseCurrentBranch     Use current branch (no isolation)"
    Write-Host "  -Force                Replace existing branch without prompt"
    Write-Host "  -Help                 Show this help"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\run-copilot.ps1                        # Launch in current directory"
    Write-Host "  .\run-copilot.ps1 C:\my-repo             # Launch in specific directory"
    Write-Host "  .\run-copilot.ps1 -Branch feature        # Create copilot/feature branch"
    Write-Host "  .\run-copilot.ps1 -Name my-session       # Custom container name"
    Write-Host "  .\run-copilot.ps1 -NetworkProxy squid    # Use monitored proxy"
    Write-Host "  .\run-copilot.ps1 -Cpu 8 -Memory 16g     # Custom resources"
    exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\..\utils\common-functions.ps1"

# Check Docker
if (-not (Test-DockerRunning)) { exit 1 }

# Resolve path
try {
    $RepoPath = Resolve-Path $RepoPath -ErrorAction Stop
} catch {
    Write-Host "❌ Error: Repository path does not exist: $RepoPath" -ForegroundColor Red
    exit 1
}

# Verify it's a git repository
if (-not (Test-Path (Join-Path $RepoPath ".git"))) {
    Write-Host "❌ Error: $RepoPath is not a git repository" -ForegroundColor Red
    Write-Host "   Run from within a git repository or provide a path to one" -ForegroundColor Yellow
    exit 1
}

$RepoName = Get-RepoName $RepoPath
$Branch = Get-CurrentBranch $RepoPath
$ContainerName = "copilot-$RepoName-$Branch"

# Convert to WSL path
$WslPath = $RepoPath -replace '^([A-Z]):', { '/mnt/' + $_.Groups[1].Value.ToLower() } -replace '\\', '/'

# Auto-detect WSL home
$WslHome = wsl bash -c 'echo $HOME' 2>$null
if (-not $WslHome) {
    Write-Host "❌ Error: Could not detect WSL home directory" -ForegroundColor Red
    Write-Host "   Make sure WSL2 is installed and running" -ForegroundColor Yellow
    exit 1
}

# Check container runtime
if (-not (Test-DockerRunning)) {
    exit 1
}

# Get container runtime command (docker or podman)
$ContainerCmd = Get-ContainerRuntime

# Get timezone
$TimeZone = (Get-TimeZone).Id

# Pull latest image
Update-AgentImage -Agent "copilot"

Write-Host "🚀 Launching GitHub Copilot CLI..." -ForegroundColor Cyan
Write-Host "📁 Repository: $RepoName" -ForegroundColor Cyan
Write-Host "🌿 Branch: $Branch" -ForegroundColor Cyan
Write-Host "🏷️  Container: $ContainerName" -ForegroundColor Cyan
Write-Host ""

# Build docker arguments
$dockerArgs = @(
    "run", "-it", "--rm",
    "--name", $ContainerName,
    "-e", "TZ=$TimeZone",
    "-v", "${WslPath}:/workspace",
    "-v", "${WslHome}/.gitconfig:/home/agentuser/.gitconfig:ro",
    "-v", "${WslHome}/.config/gh:/home/agentuser/.config/gh:ro",
    "-v", "${WslHome}/.config/github-copilot:/home/agentuser/.config/github-copilot:ro",
    "--label", "coding-agents.type=agent",
    "--label", "coding-agents.agent=copilot",
    "--label", "coding-agents.repo=$RepoName",
    "--label", "coding-agents.branch=$Branch"
)

# Add MCP secrets if they exist
if (wsl test -f "${WslHome}/.config/coding-agents/mcp-secrets.env") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/coding-agents/mcp-secrets.env:/home/agentuser/.mcp-secrets.env:ro"
}

$dockerArgs += @(
    "-w", "/workspace",
    "--security-opt", "no-new-privileges:true",
    "--cpus=$Cpu",
    "--memory=$Memory"
)

if ($Gpu) {
    $dockerArgs += "--gpus=$Gpu"
}

$dockerArgs += "coding-agents-copilot:local"

# Run container with cleanup
try {
    & $ContainerCmd $dockerArgs
} finally {
    if (Test-ContainerExists $ContainerName) {
        Write-Host ""
        if ($NoPush) {
            Push-ToLocal -ContainerName $ContainerName -SkipPush
        } else {
            Push-ToLocal -ContainerName $ContainerName
        }
    }
}
